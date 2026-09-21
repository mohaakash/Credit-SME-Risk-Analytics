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

  data.frame(
    age = cleaned_data$age,
    log_revolving_utilization = log1p(pmax(
      cleaned_data$revolving_utilization_of_unsecured_lines,
      0
    )),
    log_debt_ratio = log1p(pmax(cleaned_data$debt_ratio, 0)),
    log_monthly_income = log1p(pmax(cleaned_data$monthly_income, 0)),
    open_credit_lines = cleaned_data$number_of_open_credit_lines_and_loans,
    times_30_59 = cleaned_data$number_of_time30_59days_past_due_not_worse,
    times_60_89 = cleaned_data$number_of_time60_89days_past_due_not_worse,
    times_90 = cleaned_data$number_of_times90days_late,
    real_estate_loans = cleaned_data$number_real_estate_loans_or_lines,
    dependents = cleaned_data$number_of_dependents,
    age_missing = as.integer(is.na(cleaned_data$age)),
    monthly_income_missing = as.integer(is.na(cleaned_data$monthly_income)),
    dependents_missing = as.integer(is.na(cleaned_data$number_of_dependents)),
    time_30_59_missing = as.integer(is.na(
      cleaned_data$number_of_time30_59days_past_due_not_worse
    )),
    time_60_89_missing = as.integer(is.na(
      cleaned_data$number_of_time60_89days_past_due_not_worse
    )),
    time_90_missing = as.integer(is.na(cleaned_data$number_of_times90days_late)),
    revolving_utilization_gt_1 = as.integer(cleaned_data$revolving_utilization_gt_1),
    debt_ratio_gt_10 = as.integer(cleaned_data$debt_ratio_gt_10),
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
