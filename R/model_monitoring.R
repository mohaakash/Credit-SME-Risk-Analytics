# Reproducible monitoring diagnostics for the Phase 3 demonstration model.
#
# The source dataset has no application date or observation window. This script
# therefore compares the fixed stratified training and held-out test partitions
# as non-temporal demonstration slices. It does not create synthetic records or
# claim that the comparison represents production drift.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(readr)
})

source(file.path("R", "feature_engineering.R"))

monitoring_features <- c(
  "age",
  "monthly_income",
  "debt_ratio",
  "revolving_utilization_of_unsecured_lines",
  "number_of_open_credit_lines_and_loans",
  "number_of_time30_59days_past_due_not_worse",
  "number_of_time60_89days_past_due_not_worse",
  "number_of_times90days_late",
  "number_real_estate_loans_or_lines",
  "number_of_dependents"
)

safe_quantile <- function(values, probability) {
  finite_values <- values[is.finite(values)]
  if (length(finite_values) == 0) return(NA_real_)
  as.numeric(stats::quantile(finite_values, probability, names = FALSE, type = 7))
}

distribution_summary <- function(metric_type, variable, period, values) {
  finite_values <- values[is.finite(values)]
  tibble::tibble(
    metric_type = metric_type,
    variable = variable,
    period = period,
    row_count = length(values),
    nonmissing_count = length(finite_values),
    missing_rate = if (length(values) > 0) mean(!is.finite(values)) else NA_real_,
    mean = if (length(finite_values) > 0) mean(finite_values) else NA_real_,
    median = safe_quantile(values, 0.50),
    p01 = safe_quantile(values, 0.01),
    p25 = safe_quantile(values, 0.25),
    p75 = safe_quantile(values, 0.75),
    p99 = safe_quantile(values, 0.99),
    minimum = if (length(finite_values) > 0) min(finite_values) else NA_real_,
    maximum = if (length(finite_values) > 0) max(finite_values) else NA_real_
  )
}

psi_table <- function(metric_type, variable, reference, comparison, bin_count = 10L) {
  reference_finite <- reference[is.finite(reference)]
  comparison_finite <- comparison[is.finite(comparison)]
  output_columns <- c(
    "metric_type", "variable", "bin", "reference_count", "comparison_count",
    "reference_pct", "comparison_pct", "psi_contribution"
  )

  if (length(reference_finite) == 0 || length(comparison_finite) == 0) {
    output <- as.list(rep(NA, length(output_columns)))
    names(output) <- output_columns
    output$metric_type <- metric_type
    output$variable <- variable
    output$bin <- "unavailable"
    return(tibble::as_tibble(output))
  }

  quantile_breaks <- stats::quantile(
    reference_finite,
    probs = seq(0, 1, length.out = bin_count + 1),
    names = FALSE,
    type = 7
  )
  internal_breaks <- unique(quantile_breaks[-c(1, length(quantile_breaks))])
  breaks <- c(-Inf, internal_breaks, Inf)
  bin_labels <- paste0("bin_", seq_len(length(breaks) - 1))

  reference_bins <- cut(
    reference_finite,
    breaks = breaks,
    labels = bin_labels,
    include.lowest = TRUE,
    right = FALSE
  )
  comparison_bins <- cut(
    comparison_finite,
    breaks = breaks,
    labels = bin_labels,
    include.lowest = TRUE,
    right = FALSE
  )
  reference_counts <- table(factor(reference_bins, levels = bin_labels))
  comparison_counts <- table(factor(comparison_bins, levels = bin_labels))
  reference_pct <- as.numeric(reference_counts) / length(reference_finite)
  comparison_pct <- as.numeric(comparison_counts) / length(comparison_finite)
  epsilon <- 1e-6
  reference_safe <- pmax(reference_pct, epsilon)
  comparison_safe <- pmax(comparison_pct, epsilon)

  tibble::tibble(
    metric_type = metric_type,
    variable = variable,
    bin = bin_labels,
    reference_count = as.integer(reference_counts),
    comparison_count = as.integer(comparison_counts),
    reference_pct = reference_pct,
    comparison_pct = comparison_pct,
    psi_contribution = (comparison_safe - reference_safe) *
      log(comparison_safe / reference_safe)
  )
}

psi_interpretation <- function(value) {
  dplyr::case_when(
    is.na(value) ~ "Unavailable",
    value < 0.10 ~ "Stable demonstration",
    value < 0.25 ~ "Moderate shift",
    TRUE ~ "Substantial shift"
  )
}

calibration_by_period <- function(period, target, score) {
  keep <- is.finite(score) & !is.na(target)
  target <- target[keep]
  score <- score[keep]
  if (length(score) == 0) return(tibble::tibble())

  decile <- dplyr::ntile(dplyr::desc(score), 10)
  tibble::tibble(
    comparison_type = "non_temporal_demonstration",
    synthetic_period = FALSE,
    model = "Logistic",
    period = period,
    decile = decile,
    target = target,
    score = score
  ) |>
    dplyr::group_by(comparison_type, synthetic_period, model, period, decile) |>
    dplyr::summarise(
      borrower_count = dplyr::n(),
      predicted_default_rate = mean(score),
      observed_default_rate = mean(target),
      calibration_gap = observed_default_rate - predicted_default_rate,
      absolute_calibration_gap = abs(calibration_gap),
      .groups = "drop"
    ) |>
    dplyr::arrange(period, decile)
}

format_number <- function(values, digits = 4) {
  ifelse(is.na(values), "NA", formatC(values, format = "f", digits = digits, big.mark = ","))
}

format_percentage <- function(values, digits = 2) {
  ifelse(is.na(values), "NA", paste0(formatC(values * 100, format = "f", digits = digits), "%"))
}

markdown_table <- function(data) {
  if (nrow(data) == 0) return(c("No rows."))
  header <- paste0("| ", paste(names(data), collapse = " | "), " |")
  divider <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  rows <- apply(data, 1, function(row) paste0("| ", paste(row, collapse = " | "), " |"))
  c(header, divider, rows)
}

run_model_monitoring <- function(project_root = getwd()) {
  sqlite_path <- file.path(project_root, "data", "processed", "give_me_some_credit.sqlite")
  split_path <- file.path(project_root, "reports", "generated", "model_split_manifest.csv")
  model_path <- file.path(project_root, "models", "logistic_model.rds")
  preprocessor_path <- file.path(project_root, "models", "model_preprocessor.rds")
  generated_dir <- file.path(project_root, "reports", "generated")
  report_path <- file.path(project_root, "reports", "model-monitoring-report.md")

  required_paths <- c(sqlite_path, split_path, model_path, preprocessor_path)
  missing_paths <- required_paths[!file.exists(required_paths)]
  if (length(missing_paths) > 0) {
    stop(
      "Monitoring inputs are missing. Run R/data_cleaning.R and R/train_models.R first. Missing: ",
      paste(missing_paths, collapse = ", "),
      call. = FALSE
    )
  }

  dir.create(generated_dir, recursive = TRUE, showWarnings = FALSE)
  connection <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  cleaned <- DBI::dbReadTable(connection, "training_clean")
  split_manifest <- readr::read_csv(split_path, show_col_types = FALSE)
  if (nrow(cleaned) != nrow(split_manifest)) {
    stop("The cleaned data and model split manifest have different row counts.", call. = FALSE)
  }

  split_by_id <- split_manifest$split[match(cleaned$id, split_manifest$source_id)]
  if (anyNA(split_by_id) || !all(split_by_id %in% c("train", "test"))) {
    stop("Could not align every cleaned row to a train/test monitoring slice.", call. = FALSE)
  }

  model <- readRDS(model_path)
  preprocessor <- readRDS(preprocessor_path)
  features <- build_model_features(cleaned)
  processed_features <- apply_model_preprocessor(features, preprocessor)
  score <- as.numeric(stats::predict(model, newdata = processed_features, type = "response"))
  target <- as.integer(cleaned$serious_dlqin2yrs)

  reference_rows <- split_by_id == "train"
  comparison_rows <- split_by_id == "test"
  reference_label <- "reference_train"
  comparison_label <- "comparison_test"

  distributions <- dplyr::bind_rows(
    distribution_summary("prediction", "predicted_risk", reference_label, score[reference_rows]),
    distribution_summary("prediction", "predicted_risk", comparison_label, score[comparison_rows]),
    dplyr::bind_rows(lapply(monitoring_features, function(variable) {
      dplyr::bind_rows(
        distribution_summary("feature", variable, reference_label, cleaned[[variable]][reference_rows]),
        distribution_summary("feature", variable, comparison_label, cleaned[[variable]][comparison_rows])
      )
    }))
  )

  psi_rows <- dplyr::bind_rows(
    psi_table("prediction", "predicted_risk", score[reference_rows], score[comparison_rows]),
    dplyr::bind_rows(lapply(monitoring_features, function(variable) {
      psi_table(
        "feature",
        variable,
        cleaned[[variable]][reference_rows],
        cleaned[[variable]][comparison_rows]
      )
    }))
  )
  psi_totals <- psi_rows |>
    dplyr::group_by(metric_type, variable) |>
    dplyr::summarise(psi = sum(psi_contribution, na.rm = TRUE), .groups = "drop") |>
    dplyr::mutate(interpretation = psi_interpretation(psi))
  psi_rows <- psi_rows |>
    dplyr::left_join(psi_totals, by = c("metric_type", "variable"))

  reference_distribution <- distributions |>
    dplyr::filter(period == reference_label) |>
    dplyr::select(metric_type, variable, reference_mean = mean, reference_median = median, reference_missing_rate = missing_rate)
  comparison_distribution <- distributions |>
    dplyr::filter(period == comparison_label) |>
    dplyr::select(metric_type, variable, comparison_mean = mean, comparison_median = median, comparison_missing_rate = missing_rate)
  feature_drift <- reference_distribution |>
    dplyr::filter(metric_type == "feature") |>
    dplyr::left_join(comparison_distribution, by = c("metric_type", "variable")) |>
    dplyr::left_join(
      psi_totals |>
        dplyr::filter(metric_type == "feature") |>
        dplyr::select(metric_type, variable, psi, psi_interpretation = interpretation),
      by = c("metric_type", "variable")
    ) |>
    dplyr::mutate(
      mean_difference = comparison_mean - reference_mean,
      median_difference = comparison_median - reference_median,
      missing_rate_difference = comparison_missing_rate - reference_missing_rate
    ) |>
    dplyr::arrange(dplyr::desc(psi))

  calibration <- dplyr::bind_rows(
    calibration_by_period(reference_label, target[reference_rows], score[reference_rows]),
    calibration_by_period(comparison_label, target[comparison_rows], score[comparison_rows])
  )

  monitoring_summary <- tibble::tibble(
    check = c(
      "Monitoring data scope",
      "Temporal ordering available",
      "Reference slice",
      "Comparison slice",
      "Synthetic monitoring records",
      "Model under review",
      "PSI thresholds"
    ),
    status = c(
      "DOCUMENTED",
      "NOT_AVAILABLE",
      "AVAILABLE",
      "AVAILABLE",
      "NOT_USED",
      "AVAILABLE",
      "DOCUMENTED"
    ),
    details = c(
      "Fixed stratified train/test partitions from the Phase 3 demonstration split; not calendar periods.",
      "The source data has no application date or observation window.",
      paste0(reference_label, " (n=", sum(reference_rows), ")"),
      paste0(comparison_label, " (n=", sum(comparison_rows), ")"),
      "No synthetic rows or simulated time periods were generated.",
      "Saved raw-feature logistic baseline used by the dashboard simulator.",
      "Heuristic interpretation: <0.10 stable, 0.10-0.25 moderate, >=0.25 substantial."
    )
  )

  readr::write_csv(distributions, file.path(generated_dir, "monitoring_distributions.csv"))
  readr::write_csv(psi_rows, file.path(generated_dir, "monitoring_psi.csv"))
  readr::write_csv(feature_drift, file.path(generated_dir, "monitoring_feature_drift.csv"))
  readr::write_csv(calibration, file.path(generated_dir, "monitoring_calibration.csv"))
  readr::write_csv(monitoring_summary, file.path(generated_dir, "monitoring_summary.csv"))

  prediction_psi <- psi_totals |>
    dplyr::filter(metric_type == "prediction", variable == "predicted_risk")
  top_feature_drift <- feature_drift |>
    dplyr::select(variable, psi, psi_interpretation, missing_rate_difference, mean_difference) |>
    dplyr::slice_head(n = 5)
  comparison_calibration <- calibration |>
    dplyr::filter(period == comparison_label)
  report_lines <- c(
    "# Model monitoring report",
    "",
    "Generated by `R/model_monitoring.R` from the current cleaned SQLite input and saved Phase 3 logistic model.",
    "",
    "## Scope and limitations",
    "",
    "The source dataset has no application date, observation window, or production scoring history. This report compares the fixed stratified training and held-out test partitions as non-temporal demonstration slices. It does not represent monthly drift, production monitoring, or a simulated time series.",
    "",
    "No synthetic monitoring records or simulated periods were generated. Any operational deployment would require timestamped score data, a governed reference window, and institution-specific alert thresholds.",
    "",
    "## Monitoring scope",
    "",
    markdown_table(monitoring_summary),
    "",
    "## Prediction distribution",
    "",
    markdown_table(
      distributions |>
        dplyr::filter(metric_type == "prediction") |>
        dplyr::mutate(
          mean = format_number(mean),
          median = format_number(median),
          missing_rate = format_percentage(missing_rate)
        ) |>
        dplyr::select(period, row_count, nonmissing_count, missing_rate, mean, median)
    ),
    "",
    "## Population Stability Index",
    "",
    "PSI is calculated from reference-train quantile bins and compared with the held-out test slice. Missingness is reported separately in the feature-drift table. The thresholds below are screening heuristics, not validated model-monitoring alerts.",
    "",
    markdown_table(
      prediction_psi |>
        dplyr::mutate(psi = format_number(psi), interpretation = interpretation) |>
        dplyr::select(variable, psi, interpretation)
    ),
    "",
    "## Largest feature shifts",
    "",
    markdown_table(
      top_feature_drift |>
        dplyr::mutate(
          psi = format_number(psi),
          missing_rate_difference = format_percentage(missing_rate_difference),
          mean_difference = format_number(mean_difference)
        )
    ),
    "",
    "## Calibration check",
    "",
    "The saved raw-feature logistic baseline is recalculated by risk decile within each non-temporal slice. Decile 1 is the highest predicted-risk group. The gaps below are descriptive and do not establish future performance.",
    "",
    markdown_table(
      comparison_calibration |>
        dplyr::mutate(
          predicted_default_rate = format_percentage(predicted_default_rate),
          observed_default_rate = format_percentage(observed_default_rate),
          calibration_gap = format_percentage(calibration_gap),
          absolute_calibration_gap = format_percentage(absolute_calibration_gap)
        ) |>
        dplyr::select(period, decile, borrower_count, predicted_default_rate, observed_default_rate, calibration_gap, absolute_calibration_gap)
    ),
    "",
    "## Operational handoff",
    "",
    "Before using this workflow operationally, add a governed scoring table with score timestamp, model version, feature snapshot, realized outcome date, and data-quality status. Then calibrate alert thresholds on the institution's validation history and document ownership for investigation and remediation."
  )
  writeLines(report_lines, report_path)

  message("Monitoring diagnostics written to ", generated_dir)
  message("Monitoring report written to ", report_path)
  invisible(list(
    distributions = distributions,
    psi = psi_rows,
    feature_drift = feature_drift,
    calibration = calibration,
    summary = monitoring_summary
  ))
}

if (sys.nframe() == 0) {
  run_model_monitoring()
}
