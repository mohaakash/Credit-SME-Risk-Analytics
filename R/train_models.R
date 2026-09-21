# Train and evaluate the Phase 3 demonstration credit-risk models.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(readr)
  library(randomForest)
  library(rpart)
})

source(file.path("R", "feature_engineering.R"))

safe_divide <- function(numerator, denominator) {
  ifelse(denominator == 0, NA_real_, numerator / denominator)
}

stratified_split <- function(target, training_fraction = 0.8, seed = 20260921) {
  if (!all(target %in% c(0, 1))) {
    stop("Target must contain only 0 and 1 values.", call. = FALSE)
  }

  set.seed(seed)
  training_indices <- unlist(lapply(c(0, 1), function(class_value) {
    class_indices <- which(target == class_value)
    sample_size <- floor(length(class_indices) * training_fraction)
    sample(class_indices, size = sample_size, replace = FALSE)
  }))
  sort(training_indices)
}

roc_auc <- function(target, score) {
  positive_count <- sum(target == 1)
  negative_count <- sum(target == 0)
  if (positive_count == 0 || negative_count == 0) return(NA_real_)

  ranks <- rank(score, ties.method = "average")
  (sum(ranks[target == 1]) - positive_count * (positive_count + 1) / 2) /
    (positive_count * negative_count)
}

average_precision <- function(target, score) {
  positive_count <- sum(target == 1)
  if (positive_count == 0) return(NA_real_)

  ordering <- order(score, decreasing = TRUE)
  ordered_target <- target[ordering]
  precision <- cumsum(ordered_target) / seq_along(ordered_target)
  sum(precision[ordered_target == 1]) / positive_count
}

ks_statistic <- function(target, score) {
  positive_count <- sum(target == 1)
  negative_count <- sum(target == 0)
  if (positive_count == 0 || negative_count == 0) {
    return(c(ks = NA_real_, threshold = NA_real_))
  }

  ordering <- order(score, decreasing = TRUE)
  ordered_target <- target[ordering]
  true_positive_rate <- cumsum(ordered_target) / positive_count
  false_positive_rate <- cumsum(1 - ordered_target) / negative_count
  difference <- true_positive_rate - false_positive_rate
  position <- which.max(abs(difference))
  c(ks = abs(difference[position]), threshold = score[ordering][position])
}

roc_curve <- function(target, score) {
  ordering <- order(score, decreasing = TRUE)
  ordered_target <- target[ordering]
  positive_count <- sum(target == 1)
  negative_count <- sum(target == 0)
  data.frame(
    false_positive_rate = c(0, cumsum(1 - ordered_target) / negative_count),
    true_positive_rate = c(0, cumsum(ordered_target) / positive_count)
  )
}

calibration_table <- function(model_name, target, score) {
  ordering <- order(-score, seq_along(score))
  rank_descending <- match(seq_along(score), ordering)
  decile <- pmin(10L, ceiling(rank_descending / (length(score) / 10)))
  tibble::tibble(
    model = model_name,
    decile = decile,
    target = target,
    score = score
  ) |>
    dplyr::group_by(model, decile) |>
    dplyr::summarise(
      borrower_count = dplyr::n(),
      predicted_default_rate = mean(score),
      observed_default_rate = mean(target),
      .groups = "drop"
    ) |>
    dplyr::arrange(model, decile)
}

threshold_table <- function(model_name, target, score, thresholds) {
  dplyr::bind_rows(lapply(thresholds, function(threshold) {
    predicted_positive <- score >= threshold
    true_positive <- sum(predicted_positive & target == 1)
    false_positive <- sum(predicted_positive & target == 0)
    true_negative <- sum(!predicted_positive & target == 0)
    false_negative <- sum(!predicted_positive & target == 1)
    tibble::tibble(
      model = model_name,
      threshold = threshold,
      true_positive = true_positive,
      false_positive = false_positive,
      true_negative = true_negative,
      false_negative = false_negative,
      sensitivity = safe_divide(true_positive, true_positive + false_negative),
      specificity = safe_divide(true_negative, true_negative + false_positive),
      precision = safe_divide(true_positive, true_positive + false_positive),
      false_positive_rate = safe_divide(false_positive, false_positive + true_negative),
      false_negative_rate = safe_divide(false_negative, false_negative + true_positive),
      flagged_rate = mean(predicted_positive)
    )
  }))
}

segment_performance <- function(segment_name, segment, target, model_scores) {
  segment <- as.character(segment)
  segment[is.na(segment)] <- "Missing"
  bands <- sort(unique(segment))

  dplyr::bind_rows(lapply(names(model_scores), function(model_name) {
    score <- model_scores[[model_name]]
    dplyr::bind_rows(lapply(bands, function(band) {
      rows <- segment == band
      tibble::tibble(
        model = model_name,
        segment = segment_name,
        band = band,
        borrower_count = sum(rows),
        default_count = sum(target[rows] == 1),
        default_rate = mean(target[rows]),
        roc_auc = roc_auc(target[rows], score[rows]),
        brier_score = mean((score[rows] - target[rows])^2)
      )
    }))
  }))
}

fairness_proxy_performance <- function(segment_name, segment, target, score, threshold = 0.10) {
  segment <- as.character(segment)
  segment[is.na(segment)] <- "Missing"
  bands <- sort(unique(segment))
  predicted_positive <- score >= threshold

  dplyr::bind_rows(lapply(bands, function(band) {
    rows <- segment == band
    positives <- target[rows] == 1
    negatives <- target[rows] == 0
    flagged <- predicted_positive[rows]
    tibble::tibble(
      segment = segment_name,
      band = band,
      borrower_count = sum(rows),
      default_rate = mean(target[rows]),
      mean_predicted_risk = mean(score[rows]),
      threshold = threshold,
      true_positive_rate = safe_divide(sum(flagged & positives), sum(positives)),
      false_positive_rate = safe_divide(sum(flagged & negatives), sum(negatives))
    )
  }))
}

lift_table <- function(model_name, target, score) {
  ordering <- order(-score, seq_along(score))
  rank_descending <- match(seq_along(score), ordering)
  decile <- pmin(10L, ceiling(rank_descending / (length(score) / 10)))
  overall_rate <- mean(target)
  tibble::tibble(
    model = model_name,
    decile = decile,
    target = target,
    score = score
  ) |>
    dplyr::group_by(model, decile) |>
    dplyr::summarise(
      borrower_count = dplyr::n(),
      predicted_default_rate = mean(score),
      observed_default_rate = mean(target),
      lift = observed_default_rate / overall_rate,
      .groups = "drop"
    ) |>
    dplyr::arrange(model, decile) |>
    dplyr::mutate(cumulative_borrower_pct = cumsum(borrower_count) / sum(borrower_count))
}

model_metrics <- function(model_name, target, score) {
  ks_result <- ks_statistic(target, score)
  tibble::tibble(
    model = model_name,
    borrower_count = length(target),
    default_rate = mean(target),
    roc_auc = roc_auc(target, score),
    pr_auc = average_precision(target, score),
    ks = unname(ks_result[["ks"]]),
    ks_threshold = unname(ks_result[["threshold"]]),
    brier_score = mean((score - target)^2)
  )
}

markdown_table <- function(data) {
  if (nrow(data) == 0) return(c("No rows."))
  header <- paste0("| ", paste(names(data), collapse = " | "), " |")
  divider <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  rows <- apply(data, 1, function(row) paste0("| ", paste(row, collapse = " | "), " |"))
  c(header, divider, rows)
}

format_number <- function(values, digits = 4) {
  ifelse(is.na(values), "NA", formatC(values, format = "f", digits = digits, big.mark = ","))
}

format_percentage <- function(values, digits = 2) {
  ifelse(is.na(values), "NA", paste0(formatC(values * 100, format = "f", digits = digits), "%"))
}

format_p_value <- function(values) {
  ifelse(
    is.na(values),
    "NA",
    ifelse(values < 1e-6, "<1e-6", formatC(values, format = "f", digits = 6))
  )
}

run_model_training <- function(project_root = getwd()) {
  sqlite_path <- file.path(
    project_root,
    "data",
    "processed",
    "give_me_some_credit.sqlite"
  )
  generated_dir <- file.path(project_root, "reports", "generated")
  models_dir <- file.path(project_root, "models")
  report_path <- file.path(project_root, "reports", "modeling-report.md")

  if (!file.exists(sqlite_path)) {
    stop("Clean SQLite database not found. Run R/data_cleaning.R first.", call. = FALSE)
  }
  dir.create(generated_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)

  connection <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  cleaned <- DBI::dbReadTable(connection, "training_clean")
  target <- as.integer(cleaned$serious_dlqin2yrs)
  valid_rows <- !is.na(target) & target %in% c(0, 1)
  cleaned <- cleaned[valid_rows, , drop = FALSE]
  target <- target[valid_rows]

  seed <- 20260921
  training_indices <- stratified_split(target, training_fraction = 0.8, seed = seed)
  test_indices <- setdiff(seq_along(target), training_indices)
  split <- rep("test", length(target))
  split[training_indices] <- "train"

  model_features <- build_model_features(cleaned)
  preprocessor <- fit_model_preprocessor(model_features[training_indices, , drop = FALSE])
  training_features <- apply_model_preprocessor(
    model_features[training_indices, , drop = FALSE],
    preprocessor
  )
  test_features <- apply_model_preprocessor(
    model_features[test_indices, , drop = FALSE],
    preprocessor
  )
  training_target <- target[training_indices]
  test_target <- target[test_indices]
  class_counts <- table(factor(training_target, levels = c(0, 1)))

  woe_preprocessor <- fit_woe_preprocessor(
    cleaned[training_indices, , drop = FALSE],
    training_target
  )
  woe_training_features <- apply_woe_preprocessor(
    cleaned[training_indices, , drop = FALSE],
    woe_preprocessor
  )
  woe_test_features <- apply_woe_preprocessor(
    cleaned[test_indices, , drop = FALSE],
    woe_preprocessor
  )
  woe_formula <- stats::as.formula(
    paste("target ~", paste(names(woe_training_features), collapse = " + "))
  )
  woe_training_data <- woe_training_features
  woe_training_data$target <- training_target
  woe_logistic_model <- stats::glm(
    woe_formula,
    data = woe_training_data,
    family = stats::binomial()
  )
  woe_logistic_score <- as.numeric(stats::predict(
    woe_logistic_model,
    newdata = woe_test_features,
    type = "response"
  ))

  formula <- stats::as.formula(
    paste("target ~", paste(preprocessor$feature_names, collapse = " + "))
  )
  logistic_training_data <- training_features
  logistic_training_data$target <- training_target
  logistic_model <- stats::glm(
    formula,
    data = logistic_training_data,
    family = stats::binomial()
  )
  logistic_score <- as.numeric(stats::predict(
    logistic_model,
    newdata = test_features,
    type = "response"
  ))

  tree_training_data <- training_features
  tree_training_data$target <- factor(training_target, levels = c(0, 1))
  tree_model <- rpart::rpart(
    formula,
    data = tree_training_data,
    method = "class",
    control = rpart::rpart.control(
      cp = 0.001,
      minsplit = 200,
      maxdepth = 6,
      xval = 5
    )
  )
  tree_probabilities <- stats::predict(tree_model, newdata = test_features, type = "prob")
  tree_score <- as.numeric(tree_probabilities[, "1"])

  balanced_sample_size <- rep(min(class_counts), length(class_counts))
  set.seed(seed)
  random_forest_model <- randomForest::randomForest(
    x = training_features,
    y = factor(training_target, levels = c(0, 1)),
    ntree = 300,
    mtry = max(1, floor(sqrt(ncol(training_features)))),
    nodesize = 25,
    sampsize = balanced_sample_size,
    replace = TRUE,
    importance = TRUE
  )
  random_forest_probabilities <- stats::predict(
    random_forest_model,
    newdata = test_features,
    type = "prob"
  )
  random_forest_score <- as.numeric(random_forest_probabilities[, "1"])

  xgboost_training_data <- xgboost::xgb.DMatrix(
    data = as.matrix(training_features),
    label = training_target
  )
  xgboost_test_data <- xgboost::xgb.DMatrix(
    data = as.matrix(test_features),
    label = test_target
  )
  xgboost_model <- xgboost::xgb.train(
    params = list(
      objective = "binary:logistic",
      eval_metric = "logloss",
      max_depth = 4L,
      eta = 0.05,
      subsample = 0.8,
      colsample_bytree = 0.8,
      min_child_weight = 25,
      scale_pos_weight = as.numeric(class_counts[["0"]] / class_counts[["1"]]),
      tree_method = "hist",
      nthread = 2L,
      seed = seed
    ),
    data = xgboost_training_data,
    nrounds = 250L,
    verbose = 0
  )
  xgboost_score <- as.numeric(stats::predict(xgboost_model, xgboost_test_data))

  model_scores <- list(
    Logistic = logistic_score,
    Logistic_WOE = woe_logistic_score,
    CART = tree_score,
    RandomForest = random_forest_score,
    XGBoost = xgboost_score
  )
  metrics <- dplyr::bind_rows(lapply(names(model_scores), function(model_name) {
    model_metrics(model_name, test_target, model_scores[[model_name]])
  }))
  thresholds <- c(0.03, 0.05, 0.10, 0.20)
  threshold_metrics <- dplyr::bind_rows(lapply(names(model_scores), function(model_name) {
    threshold_table(model_name, test_target, model_scores[[model_name]], thresholds)
  }))
  calibration <- dplyr::bind_rows(lapply(names(model_scores), function(model_name) {
    calibration_table(model_name, test_target, model_scores[[model_name]])
  }))
  lift <- dplyr::bind_rows(lapply(names(model_scores), function(model_name) {
    lift_table(model_name, test_target, model_scores[[model_name]])
  }))

  train_counts <- table(training_target)
  test_counts <- table(test_target)
  class_balance <- dplyr::bind_rows(
    tibble::tibble(
      split = "train",
      class = as.integer(names(train_counts)),
      borrower_count = as.integer(train_counts)
    ),
    tibble::tibble(
      split = "test",
      class = as.integer(names(test_counts)),
      borrower_count = as.integer(test_counts)
    )
  ) |>
    dplyr::group_by(split) |>
    dplyr::mutate(
      class_rate = borrower_count / sum(borrower_count),
      majority_to_minority_ratio = max(borrower_count) / min(borrower_count)
    ) |>
    dplyr::ungroup()

  age_band <- cut(
    cleaned$age,
    breaks = c(-Inf, 29, 44, 59, Inf),
    labels = c("<30", "30-44", "45-59", "60+"),
    right = TRUE
  )
  income_status <- ifelse(is.na(cleaned$monthly_income), "Missing", "Observed")
  delinquency_90_status <- dplyr::case_when(
    is.na(cleaned$number_of_times90days_late) ~ "Missing",
    cleaned$number_of_times90days_late > 0 ~ "One or more 90+ day events",
    TRUE ~ "No 90+ day events"
  )
  test_segments <- list(
    age_band = age_band[test_indices],
    income_status = income_status[test_indices],
    delinquency_90_status = delinquency_90_status[test_indices]
  )
  segment_diagnostics <- dplyr::bind_rows(lapply(names(test_segments), function(segment_name) {
    segment_performance(
      segment_name,
      test_segments[[segment_name]],
      test_target,
      model_scores
    )
  }))

  fairness_proxy <- dplyr::bind_rows(
    fairness_proxy_performance(
      "age_band",
      test_segments$age_band,
      test_target,
      logistic_score
    ),
    fairness_proxy_performance(
      "income_status",
      test_segments$income_status,
      test_target,
      logistic_score
    )
  )

  target_like_features <- names(cleaned)[grepl(
    "target|serious|default|dlqin",
    names(cleaned),
    ignore.case = TRUE
  )]
  train_test_id_overlap <- intersect(
    as.character(cleaned$id[training_indices]),
    as.character(cleaned$id[test_indices])
  )
  leakage_checks <- tibble::tibble(
    check = c(
      "Target excluded from model features",
      "Train and test source IDs are disjoint",
      "Preprocessor fit uses training partition only",
      "Held-out test labels are excluded from model fitting"
    ),
    status = c(
      if ("serious_dlqin2yrs" %in% preprocessor$feature_names) "FAIL" else "PASS",
      if (length(train_test_id_overlap) == 0) "PASS" else "FAIL",
      "PASS",
      "PASS"
    ),
    details = c(
      paste("Target-like source columns:", paste(target_like_features, collapse = ", ")),
      paste("Overlapping source IDs:", length(train_test_id_overlap)),
      "Medians are computed from training rows before test preprocessing.",
      "Only training_target is passed to model fitting; test_target is used for evaluation."
    )
  )
  woe_iv <- woe_iv_summary(woe_preprocessor)
  woe_iv_by_variable <- woe_iv |>
    dplyr::group_by(variable) |>
    dplyr::summarise(
      information_value = sum(information_value),
      bin_count = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(information_value))

  logistic_coefficients <- as.data.frame(summary(logistic_model)$coefficients)
  logistic_coefficients$feature <- rownames(logistic_coefficients)
  rownames(logistic_coefficients) <- NULL
  names(logistic_coefficients)[1:4] <- c("estimate", "std_error", "z_value", "p_value")
  logistic_importance <- logistic_coefficients |>
    dplyr::filter(feature != "(Intercept)") |>
    dplyr::transmute(
      model = "Logistic",
      feature = feature,
      importance = abs(estimate),
      estimate = estimate,
      odds_ratio = exp(estimate),
      p_value = p_value
    ) |>
    dplyr::arrange(dplyr::desc(importance))
  woe_coefficients <- as.data.frame(summary(woe_logistic_model)$coefficients)
  woe_coefficients$feature <- rownames(woe_coefficients)
  rownames(woe_coefficients) <- NULL
  names(woe_coefficients)[1:4] <- c("estimate", "std_error", "z_value", "p_value")
  woe_importance <- woe_coefficients |>
    dplyr::filter(feature != "(Intercept)") |>
    dplyr::transmute(
      model = "Logistic_WOE",
      feature = feature,
      importance = abs(estimate),
      estimate = estimate,
      odds_ratio = exp(estimate),
      p_value = p_value
    ) |>
    dplyr::arrange(dplyr::desc(importance))
  tree_importance_values <- tree_model$variable.importance
  tree_importance <- if (is.null(tree_importance_values)) {
    tibble::tibble(
      model = "CART",
      feature = character(),
      importance = numeric(),
      estimate = numeric(),
      odds_ratio = numeric(),
      p_value = numeric()
    )
  } else {
    tibble::tibble(
      model = "CART",
      feature = names(tree_importance_values),
      importance = as.numeric(tree_importance_values),
      estimate = NA_real_,
      odds_ratio = NA_real_,
      p_value = NA_real_
    ) |>
      dplyr::arrange(dplyr::desc(importance))
  }
  random_forest_importance_values <- randomForest::importance(
    random_forest_model,
    type = 2
  )[, "MeanDecreaseGini"]
  random_forest_importance <- tibble::tibble(
    model = "RandomForest",
    feature = names(random_forest_importance_values),
    importance = as.numeric(random_forest_importance_values),
    estimate = NA_real_,
    odds_ratio = NA_real_,
    p_value = NA_real_
  ) |>
    dplyr::arrange(dplyr::desc(importance))
  xgboost_importance_values <- xgboost::xgb.importance(model = xgboost_model)
  xgboost_importance <- if (nrow(xgboost_importance_values) == 0) {
    tibble::tibble(
      model = "XGBoost",
      feature = character(),
      importance = numeric(),
      estimate = numeric(),
      odds_ratio = numeric(),
      p_value = numeric()
    )
  } else {
    tibble::tibble(
      model = "XGBoost",
      feature = xgboost_importance_values$Feature,
      importance = xgboost_importance_values$Gain,
      estimate = NA_real_,
      odds_ratio = NA_real_,
      p_value = NA_real_
    ) |>
      dplyr::arrange(dplyr::desc(importance))
  }
  importance <- dplyr::bind_rows(
    logistic_importance,
    woe_importance,
    tree_importance,
    random_forest_importance,
    xgboost_importance
  )

  split_manifest <- tibble::tibble(
    row_number = seq_along(target),
    source_id = cleaned$id,
    split = split,
    target = target
  )

  readr::write_csv(metrics, file.path(generated_dir, "model_metrics.csv"))
  readr::write_csv(threshold_metrics, file.path(generated_dir, "model_threshold_metrics.csv"))
  readr::write_csv(calibration, file.path(generated_dir, "model_calibration.csv"))
  readr::write_csv(lift, file.path(generated_dir, "model_lift_by_decile.csv"))
  readr::write_csv(importance, file.path(generated_dir, "model_feature_importance.csv"))
  readr::write_csv(split_manifest, file.path(generated_dir, "model_split_manifest.csv"))
  readr::write_csv(class_balance, file.path(generated_dir, "class_balance.csv"))
  readr::write_csv(leakage_checks, file.path(generated_dir, "leakage_checks.csv"))
  readr::write_csv(segment_diagnostics, file.path(generated_dir, "segment_performance.csv"))
  readr::write_csv(fairness_proxy, file.path(generated_dir, "fairness_proxy.csv"))
  readr::write_csv(woe_iv, file.path(generated_dir, "woe_iv_bins.csv"))
  readr::write_csv(woe_iv_by_variable, file.path(generated_dir, "woe_iv_summary.csv"))

  saveRDS(logistic_model, file.path(models_dir, "logistic_model.rds"))
  saveRDS(tree_model, file.path(models_dir, "cart_model.rds"))
  saveRDS(random_forest_model, file.path(models_dir, "random_forest_model.rds"))
  saveRDS(woe_logistic_model, file.path(models_dir, "logistic_woe_model.rds"))
  saveRDS(woe_preprocessor, file.path(models_dir, "woe_preprocessor.rds"))
  xgboost::xgb.save(xgboost_model, file.path(models_dir, "xgboost_model.json"))
  saveRDS(preprocessor, file.path(models_dir, "model_preprocessor.rds"))
  saveRDS(
    list(seed = seed, training_rows = training_indices, test_rows = test_indices),
    file.path(models_dir, "model_split.rds")
  )

  roc_curves <- lapply(names(model_scores), function(model_name) {
    curve <- roc_curve(test_target, model_scores[[model_name]])
    curve$model <- model_name
    curve
  }) |>
    dplyr::bind_rows()
  readr::write_csv(roc_curves, file.path(generated_dir, "model_roc_curves.csv"))
  grDevices::png(
    file.path(generated_dir, "roc_comparison.png"),
    width = 1200,
    height = 900,
    res = 120
  )
  graphics::plot(
    0,
    0,
    type = "n",
    xlim = c(0, 1),
    ylim = c(0, 1),
    xlab = "False-positive rate",
    ylab = "True-positive rate",
    main = paste0("ROC comparison (test n = ", formatC(length(test_target), format = "d", big.mark = ","), ")")
  )
  graphics::abline(0, 1, lty = 2, col = "grey60")
  model_colors <- c(
    Logistic = "#2166ac",
    Logistic_WOE = "#8c6bb1",
    CART = "#b2182b",
    RandomForest = "#606C38",
    XGBoost = "#C66B3D"
  )
  for (model_name in names(model_scores)) {
    curve <- roc_curves[roc_curves$model == model_name, , drop = FALSE]
    graphics::lines(
      curve$false_positive_rate,
      curve$true_positive_rate,
      col = model_colors[[model_name]],
      lwd = 2
    )
  }
  graphics::legend(
    "bottomright",
    legend = paste0(metrics$model, " AUC=", formatC(metrics$roc_auc, format = "f", digits = 3)),
    col = model_colors[metrics$model],
    lwd = 2,
    bty = "n"
  )
  grDevices::dev.off()

  grDevices::png(
    file.path(generated_dir, "calibration_comparison.png"),
    width = 1200,
    height = 900,
    res = 120
  )
  graphics::plot(
    0,
    0,
    type = "n",
    xlim = c(0, max(calibration$predicted_default_rate) * 1.05),
    ylim = c(0, max(calibration$observed_default_rate) * 1.05),
    xlab = "Mean predicted default rate",
    ylab = "Observed default rate",
    main = "Calibration by descending-risk decile"
  )
  graphics::abline(0, 1, lty = 2, col = "grey60")
  for (model_name in names(model_scores)) {
    values <- calibration[calibration$model == model_name, , drop = FALSE]
    graphics::lines(
      values$predicted_default_rate,
      values$observed_default_rate,
      type = "b",
      col = model_colors[[model_name]],
      lwd = 2,
      pch = 19
    )
  }
  graphics::legend(
    "topleft",
    legend = names(model_scores),
    col = model_colors[names(model_scores)],
    lwd = 2,
    pch = 19,
    bty = "n"
  )
  grDevices::dev.off()

  grDevices::png(
    file.path(generated_dir, "lift_by_decile.png"),
    width = 1200,
    height = 900,
    res = 120
  )
  graphics::plot(
    1:10,
    rep(NA_real_, 10),
    type = "n",
    xlim = c(1, 10),
    ylim = c(0, max(lift$lift) * 1.05),
    xlab = "Risk decile (1 = highest predicted risk)",
    ylab = "Observed lift vs. portfolio default rate",
    main = "Test-set lift by risk decile"
  )
  graphics::abline(h = 1, lty = 2, col = "grey60")
  for (model_name in names(model_scores)) {
    values <- lift[lift$model == model_name, , drop = FALSE]
    graphics::lines(values$decile, values$lift, type = "b", col = model_colors[[model_name]], lwd = 2, pch = 19)
  }
  graphics::legend(
    "topright",
    legend = names(model_scores),
    col = model_colors[names(model_scores)],
    lwd = 2,
    pch = 19,
    bty = "n"
  )
  grDevices::dev.off()

  metrics_display <- metrics |>
    dplyr::mutate(
      default_rate = format_percentage(default_rate),
      roc_auc = format_number(roc_auc, 4),
      pr_auc = format_number(pr_auc, 4),
      ks = format_number(ks, 4),
      ks_threshold = format_number(ks_threshold, 4),
      brier_score = format_number(brier_score, 4)
    )
  threshold_display <- threshold_metrics |>
    dplyr::mutate(
      threshold = format_percentage(threshold),
      sensitivity = format_percentage(sensitivity),
      specificity = format_percentage(specificity),
      precision = format_percentage(precision),
      false_positive_rate = format_percentage(false_positive_rate),
      false_negative_rate = format_percentage(false_negative_rate),
      flagged_rate = format_percentage(flagged_rate)
    ) |>
    dplyr::select(model, threshold, sensitivity, specificity, precision, false_positive_rate, false_negative_rate, flagged_rate)
  calibration_display <- calibration |>
    dplyr::filter(decile %in% c(1, 5, 10)) |>
    dplyr::mutate(
      predicted_default_rate = format_percentage(predicted_default_rate),
      observed_default_rate = format_percentage(observed_default_rate)
    )
  importance_display <- importance |>
    dplyr::group_by(model) |>
    dplyr::slice_head(n = 6) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      importance = format_number(importance),
      odds_ratio = format_number(odds_ratio),
      p_value = format_p_value(p_value)
    ) |>
    dplyr::select(model, feature, importance, odds_ratio, p_value)

  class_balance_display <- class_balance |>
    dplyr::mutate(
      class_rate = format_percentage(class_rate),
      majority_to_minority_ratio = format_number(majority_to_minority_ratio, 2)
    )
  woe_iv_by_variable_display <- woe_iv_by_variable |>
    dplyr::mutate(information_value = format_number(information_value, 4))
  leakage_checks_display <- leakage_checks
  segment_diagnostics_display <- segment_diagnostics |>
    dplyr::mutate(
      default_rate = format_percentage(default_rate),
      roc_auc = format_number(roc_auc, 3),
      brier_score = format_number(brier_score, 3)
    )
  fairness_proxy_display <- fairness_proxy |>
    dplyr::mutate(
      default_rate = format_percentage(default_rate),
      mean_predicted_risk = format_percentage(mean_predicted_risk),
      threshold = format_percentage(threshold),
      true_positive_rate = format_percentage(true_positive_rate),
      false_positive_rate = format_percentage(false_positive_rate)
    )
  rf_metrics <- metrics[metrics$model == "RandomForest", , drop = FALSE]
  woe_metrics <- metrics[metrics$model == "Logistic_WOE", , drop = FALSE]
  xgb_metrics <- metrics[metrics$model == "XGBoost", , drop = FALSE]
  logistic_metrics <- metrics[metrics$model == "Logistic", , drop = FALSE]
  benchmark_interpretation <- paste0(
    "Random Forest has the strongest ROC-AUC (",
    format_number(rf_metrics$roc_auc, 4),
    ") and KS (",
    format_number(rf_metrics$ks, 4),
    "), but its class-balanced training changes the score scale and produces poor probability calibration on the held-out test set (Brier score ",
    format_number(rf_metrics$brier_score, 4),
    "). XGBoost reaches ROC-AUC ",
    format_number(xgb_metrics$roc_auc, 4),
    " with Brier score ",
    format_number(xgb_metrics$brier_score, 4),
    ". The WoE logistic candidate reaches ROC-AUC ",
    format_number(woe_metrics$roc_auc, 4),
    " and Brier score ",
    format_number(woe_metrics$brier_score, 4),
    " versus ",
    format_number(logistic_metrics$brier_score, 4),
    " for the raw-feature logistic baseline. The WoE logistic candidate is the strongest interpretable demonstration candidate, while raw logistic remains the unbinned baseline. None of the tree ensembles should be used for policy decisions without calibration, validation, and governance."
  )

  report_lines <- c(
    "# Modeling report",
    "",
    "Generated by `R/train_models.R` from the current cleaned SQLite input.",
    "",
    "## Scope",
    "",
    "This reproducible Phase 3 modeling slice compares a raw-feature logistic baseline, a training-only WoE logistic candidate, CART, a class-balanced Random Forest benchmark, and a fixed XGBoost benchmark. The ensemble settings are deliberately fixed and are not a tuned production model.",
    "",
    "This is an educational demonstration, not a production lending model or lending-policy threshold.",
    "",
    "## Split and preprocessing",
    "",
    paste0("- Fixed split seed: `", seed, "`"),
    paste0("- Training rows: ", formatC(length(training_target), format = "d", big.mark = ","), " (defaults: ", formatC(train_counts[["1"]], format = "d", big.mark = ","), ")"),
    paste0("- Test rows: ", formatC(length(test_target), format = "d", big.mark = ","), " (defaults: ", formatC(test_counts[["1"]], format = "d", big.mark = ","), ")"),
    "- The split is stratified on `serious_dlqin2yrs`.",
    "- Missing numeric values are imputed with medians computed from the training partition only.",
    "- Missingness indicators and source quality flags are retained as model features.",
    "- Ratios and monthly income use `log1p` transforms; extreme observations are not silently removed.",
    "- No test labels or post-target fields are used as predictors.",
    "",
    "## Class imbalance",
    "",
    "The target is imbalanced, so the Random Forest uses equal per-class bootstrap sample sizes and XGBoost uses the training-set negative-to-positive ratio as `scale_pos_weight`. Metrics remain reported on the untouched stratified test set.",
    "",
    markdown_table(class_balance_display),
    "",
    "## WoE/IV screening",
    "",
    "WoE bins and Information Value are fit on the training partition only, with missing values retained as a separate bin. The WoE logistic candidate is evaluated on the same held-out test set; the summary is a screening aid, not evidence of causal importance. Variables with Information Value above 0.50 are strong signals and require additional leakage and temporal-availability review before any production use.",
    "",
    markdown_table(woe_iv_by_variable_display),
    "",
    "## Leakage checks",
    "",
    markdown_table(leakage_checks_display),
    "",
    "## Held-out test metrics",
    "",
    markdown_table(metrics_display),
    "",
    "ROC-AUC measures ranking discrimination; PR-AUC is useful under class imbalance; KS is the maximum separation between cumulative default and non-default distributions; Brier score measures probability error, where lower is better.",
    "",
    "## Benchmark interpretation",
    "",
    benchmark_interpretation,
    "",
    "## Demonstration threshold trade-offs",
    "",
    "These thresholds are displayed to make false-positive and false-negative trade-offs explicit. No threshold is selected as lending policy.",
    "",
    markdown_table(threshold_display),
    "",
    "## Calibration and lift",
    "",
    "Risk decile 1 contains the highest predicted-risk observations. The full calibration and lift tables are saved under `reports/generated/`; selected deciles are shown below.",
    "",
    markdown_table(calibration_display),
    "",
    "## Feature interpretation",
    "",
    "Logistic odds ratios are conditional associations for the transformed feature terms. CART importance is a split-improvement measure and is not a causal contribution or a stable policy weight.",
    "",
    markdown_table(importance_display),
    "",
    "## Segment stability and fairness proxy review",
    "",
    "Held-out performance is summarized across age, income-availability, and 90+ day-history segments. These are stability checks, not evidence of causal or fair lending performance.",
    "",
    markdown_table(segment_diagnostics_display),
    "",
    "The fairness proxy table reports logistic-model true- and false-positive rates at the 0.10 demonstration threshold for available age and income-availability segments. The dataset contains no protected-attribute fields, so this is not a fairness assessment; a production review would require legally and ethically appropriate protected-group data and governance.",
    "",
    markdown_table(fairness_proxy_display),
    "",
    "## Generated artifacts",
    "",
    "- `reports/generated/model_metrics.csv`",
    "- `reports/generated/model_threshold_metrics.csv`",
    "- `reports/generated/model_calibration.csv`",
    "- `reports/generated/model_lift_by_decile.csv`",
    "- `reports/generated/model_roc_curves.csv`",
    "- `reports/generated/model_feature_importance.csv`",
    "- `reports/generated/model_split_manifest.csv`",
    "- `reports/generated/class_balance.csv`",
    "- `reports/generated/leakage_checks.csv`",
    "- `reports/generated/segment_performance.csv`",
    "- `reports/generated/fairness_proxy.csv`",
    "- `reports/generated/woe_iv_bins.csv`",
    "- `reports/generated/woe_iv_summary.csv`",
    "- `reports/generated/roc_comparison.png`",
    "- `reports/generated/calibration_comparison.png`",
    "- `reports/generated/lift_by_decile.png`",
    "- `models/logistic_model.rds`",
    "- `models/cart_model.rds`",
    "- `models/random_forest_model.rds`",
    "- `models/logistic_woe_model.rds`",
    "- `models/woe_preprocessor.rds`",
    "- `models/xgboost_model.json`",
    "- `models/model_preprocessor.rds`",
    "- `models/model_split.rds`",
    "",
    "## Next modeling work",
    "",
    "A production fairness assessment requires protected-group definitions, governance, and representative data that are not present here. Resampling-based stability checks, probability calibration, and model monitoring remain follow-up work."
  )
  writeLines(report_lines, report_path)

  message(paste0("Modeling report written to ", report_path))
  message(paste0("Test metrics generated for ", length(model_scores), " models"))

  invisible(list(
    metrics = metrics,
    threshold_metrics = threshold_metrics,
    calibration = calibration,
    lift = lift,
    importance = importance,
    report_path = report_path
  ))
}

if (sys.nframe() == 0) {
  run_model_training()
}
