# Feature construction and leakage-safe preprocessing for model training.

model_feature_names <- function() {
  c(
    "age",
    "log_revolving_utilization",
    "log_debt_ratio",
    "log_monthly_income",
    "open_credit_lines",
    "times_30_59",
    "times_60_89",
    "times_90",
    "real_estate_loans",
    "dependents",
    "age_missing",
    "monthly_income_missing",
    "dependents_missing",
    "time_30_59_missing",
    "time_60_89_missing",
    "time_90_missing",
    "revolving_utilization_gt_1",
    "debt_ratio_gt_10"
  )
}

build_model_features <- function(cleaned_data) {
  required_columns <- c(
    "age",
    "revolving_utilization_of_unsecured_lines",
    "debt_ratio",
    "monthly_income",
    "number_of_open_credit_lines_and_loans",
    "number_of_time30_59days_past_due_not_worse",
    "number_of_time60_89days_past_due_not_worse",
    "number_of_times90days_late",
    "number_real_estate_loans_or_lines",
    "number_of_dependents",
    "revolving_utilization_gt_1",
    "debt_ratio_gt_10"
  )
  missing_columns <- setdiff(required_columns, names(cleaned_data))
  if (length(missing_columns) > 0) {
    stop(
      "Cleaned data is missing model inputs: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  income_is_missing <- is.na(cleaned_data$monthly_income) |
    (if ("monthly_income_missing" %in% names(cleaned_data)) {
      as.logical(cleaned_data$monthly_income_missing)
    } else {
      FALSE
    })

  # When monthly income is missing, Kaggle debt_ratio records raw monthly debt in dollars.
  # For observed income, cap extreme debt_ratio values at 10 to eliminate extreme recording errors.
  # Missing income sets the DTI ratio to NA so it is cleanly imputed by the training median.
  dti_observed <- ifelse(
    income_is_missing,
    NA_real_,
    pmin(pmax(cleaned_data$debt_ratio, 0), 10)
  )

  data.frame(
    age = cleaned_data$age,
    log_revolving_utilization = log1p(pmax(
      cleaned_data$revolving_utilization_of_unsecured_lines,
      0
    )),
    log_debt_ratio = log1p(dti_observed),
    log_monthly_income = log1p(pmax(cleaned_data$monthly_income, 0)),
    open_credit_lines = cleaned_data$number_of_open_credit_lines_and_loans,
    times_30_59 = cleaned_data$number_of_time30_59days_past_due_not_worse,
    times_60_89 = cleaned_data$number_of_time60_89days_past_due_not_worse,
    times_90 = cleaned_data$number_of_times90days_late,
    real_estate_loans = cleaned_data$number_real_estate_loans_or_lines,
    dependents = cleaned_data$number_of_dependents,
    age_missing = as.integer(is.na(cleaned_data$age)),
    monthly_income_missing = as.integer(income_is_missing),
    dependents_missing = as.integer(is.na(cleaned_data$number_of_dependents)),
    time_30_59_missing = as.integer(is.na(
      cleaned_data$number_of_time30_59days_past_due_not_worse
    )),
    time_60_89_missing = as.integer(is.na(
      cleaned_data$number_of_time60_89days_past_due_not_worse
    )),
    time_90_missing = as.integer(is.na(cleaned_data$number_of_times90days_late)),
    revolving_utilization_gt_1 = as.integer(cleaned_data$revolving_utilization_gt_1),
    debt_ratio_gt_10 = as.integer(!income_is_missing & cleaned_data$debt_ratio > 10),
    check.names = FALSE
  )
}

fit_model_preprocessor <- function(training_features) {
  feature_names <- model_feature_names()
  missing_columns <- setdiff(feature_names, names(training_features))
  if (length(missing_columns) > 0) {
    stop(
      "Training features are missing: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  medians <- vapply(
    training_features[feature_names],
    function(values) {
      finite_values <- values[is.finite(values)]
      if (length(finite_values) == 0) 0 else stats::median(finite_values)
    },
    numeric(1)
  )

  list(
    feature_names = feature_names,
    medians = medians,
    missing_treatment = "Numeric missing values are imputed with training-set medians; missingness indicators are retained."
  )
}

apply_model_preprocessor <- function(features, preprocessor) {
  result <- features[preprocessor$feature_names]
  for (feature in preprocessor$feature_names) {
    missing <- is.na(result[[feature]]) | !is.finite(result[[feature]])
    result[[feature]][missing] <- preprocessor$medians[[feature]]
  }
  result
}

woe_source_variables <- function() {
  c(
    "age",
    "revolving_utilization_of_unsecured_lines",
    "debt_ratio",
    "monthly_income",
    "number_of_open_credit_lines_and_loans",
    "number_of_time30_59days_past_due_not_worse",
    "number_of_time60_89days_past_due_not_worse",
    "number_of_times90days_late",
    "number_real_estate_loans_or_lines",
    "number_of_dependents"
  )
}

woe_bin_values <- function(values, breaks) {
  bins <- rep("Missing", length(values))
  observed <- !is.na(values) & is.finite(values)
  bins[observed] <- as.character(cut(
    values[observed],
    breaks = breaks,
    include.lowest = TRUE,
    right = TRUE
  ))
  bins
}

fit_woe_preprocessor <- function(data, target, variables = woe_source_variables(), max_bins = 5L) {
  missing_columns <- setdiff(c(variables, "serious_dlqin2yrs"), names(data))
  if (length(missing_columns) > 0) {
    stop(
      "WoE data is missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(target) != nrow(data) || !all(target %in% c(0, 1))) {
    stop("WoE target must align with data and contain only 0 and 1.", call. = FALSE)
  }

  mappings <- lapply(variables, function(variable) {
    values <- data[[variable]]
    # Special treatment for debt_ratio: when monthly_income is missing, debt_ratio is dollar debt
    if (variable == "debt_ratio" && "monthly_income" %in% names(data)) {
      values[is.na(data$monthly_income)] <- NA_real_
      values[!is.na(values)] <- pmin(values[!is.na(values)], 10)
    }
    finite_values <- values[!is.na(values) & is.finite(values)]
    unique_values <- sort(unique(finite_values))
    if (length(unique_values) < 2) {
      breaks <- c(-Inf, Inf)
    } else {
      quantiles <- stats::quantile(
        finite_values,
        probs = seq(0, 1, length.out = max_bins + 1),
        na.rm = TRUE,
        names = FALSE,
        type = 7
      )
      breaks <- unique(c(-Inf, quantiles[-c(1, length(quantiles))], Inf))
    }
    bins <- woe_bin_values(values, breaks)
    levels <- sort(unique(bins))
    good_count <- vapply(levels, function(level) sum(target[bins == level] == 0), integer(1))
    bad_count <- vapply(levels, function(level) sum(target[bins == level] == 1), integer(1))
    smoothing <- 0.5
    good_distribution <- (good_count + smoothing) / (sum(good_count) + smoothing * length(levels))
    bad_distribution <- (bad_count + smoothing) / (sum(bad_count) + smoothing * length(levels))
    woe <- log(good_distribution / bad_distribution)
    information_value <- (good_distribution - bad_distribution) * woe
    list(
      variable = variable,
      breaks = breaks,
      mapping = data.frame(
        bin = levels,
        good_count = good_count,
        bad_count = bad_count,
        good_distribution = good_distribution,
        bad_distribution = bad_distribution,
        woe = woe,
        information_value = information_value,
        stringsAsFactors = FALSE
      )
    )
  })
  names(mappings) <- variables
  list(
    variables = variables,
    mappings = mappings,
    max_bins = max_bins,
    missing_treatment = "Missing values are retained as a separate WoE bin; bin boundaries are fit on the training partition only."
  )
}

apply_woe_preprocessor <- function(data, preprocessor) {
  result <- data.frame(row.names = seq_len(nrow(data)))
  for (variable in preprocessor$variables) {
    mapping <- preprocessor$mappings[[variable]]$mapping
    values <- data[[variable]]
    if (variable == "debt_ratio" && "monthly_income" %in% names(data)) {
      values[is.na(data$monthly_income)] <- NA_real_
      values[!is.na(values)] <- pmin(values[!is.na(values)], 10)
    }
    bins <- woe_bin_values(values, preprocessor$mappings[[variable]]$breaks)
    lookup <- stats::setNames(mapping$woe, mapping$bin)
    values <- unname(lookup[bins])
    values[is.na(values)] <- 0
    result[[paste0("woe_", variable)]] <- as.numeric(values)
  }
  result
}

woe_iv_summary <- function(preprocessor) {
  dplyr::bind_rows(lapply(preprocessor$mappings, function(item) {
    mapping <- item$mapping
    data.frame(
      variable = item$variable,
      bin = mapping$bin,
      good_count = mapping$good_count,
      bad_count = mapping$bad_count,
      woe = mapping$woe,
      information_value = mapping$information_value,
      stringsAsFactors = FALSE
    )
  }))
}
