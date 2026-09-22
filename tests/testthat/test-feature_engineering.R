# Unit Tests: Feature Engineering & WoE Calculations

get_project_root <- function() {
  candidates <- c(".", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "data", "processed", "give_me_some_credit.sqlite"))) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  stop("Could not locate project root directory.")
}

root <- get_project_root()
source(file.path(root, "R", "feature_engineering.R"))

test_that("WoE and IV math are mathematically consistent and non-infinite", {
  # Synthetic sample dataset with typical credit risk structure
  set.seed(42)
  n <- 500
  sample_df <- data.frame(
    age = rnorm(n, 50, 10),
    monthly_income = c(rep(NA, 50), rlnorm(450, 8, 0.5)),
    debt_ratio = c(rlnorm(50, 7, 0.5), runif(450, 0.1, 0.8)),
    revolving_utilization_of_unsecured_lines = runif(n, 0.05, 1.2),
    number_of_open_credit_lines_and_loans = rpois(n, 8),
    number_of_time30_59days_past_due_not_worse = rpois(n, 0.3),
    number_of_time60_89days_past_due_not_worse = rpois(n, 0.1),
    number_of_times90days_late = rpois(n, 0.05),
    number_real_estate_loans_or_lines = rpois(n, 1),
    number_of_dependents = rpois(n, 1),
    revolving_utilization_gt_1 = 0,
    debt_ratio_gt_10 = 0
  )
  sample_df$revolving_utilization_gt_1 <- as.integer(sample_df$revolving_utilization_of_unsecured_lines > 1)
  sample_df$debt_ratio_gt_10 <- as.integer(!is.na(sample_df$monthly_income) & sample_df$debt_ratio > 10)
  target <- rbinom(n, 1, 0.07)
  sample_df$serious_dlqin2yrs <- target
  
  woe_prep <- fit_woe_preprocessor(sample_df, target, max_bins = 5L)
  
  # Ensure all variables have mappings
  expect_true(length(woe_prep$mappings) > 0)
  
  # Ensure IV summary calculates finite, non-negative values
  iv_summary <- woe_iv_summary(woe_prep)
  expect_true(nrow(iv_summary) > 0)
  expect_true(all(is.finite(iv_summary$iv)))
  expect_true(all(iv_summary$iv >= 0))
  
  # Apply WoE transformations to dataset
  transformed <- apply_woe_preprocessor(sample_df, woe_prep)
  expect_true(all(vapply(transformed, function(col) all(is.finite(col)), logical(1))))
})

test_that("Debt ratio decoupling handles missing income correctly", {
  test_df <- data.frame(
    age = c(45, 50),
    revolving_utilization_of_unsecured_lines = c(0.2, 0.8),
    debt_ratio = c(1500, 0.35),
    monthly_income = c(NA, 5000),
    number_of_open_credit_lines_and_loans = c(5, 10),
    number_of_time30_59days_past_due_not_worse = c(0, 1),
    number_of_time60_89days_past_due_not_worse = c(0, 0),
    number_of_times90days_late = c(0, 0),
    number_real_estate_loans_or_lines = c(1, 2),
    number_of_dependents = c(0, 2),
    revolving_utilization_gt_1 = c(0, 0),
    debt_ratio_gt_10 = c(0, 0)
  )
  
  features <- build_model_features(test_df)
  
  # Missing income row should have monthly_income_missing == 1
  expect_equal(features$monthly_income_missing, c(1, 0))
  
  # Observed DTI should be finite and missing DTI should be NA before imputation
  expect_true(is.na(features$log_debt_ratio[1]))
  expect_true(is.finite(features$log_debt_ratio[2]))
  
  # Test imputation via preprocessor
  prep <- fit_model_preprocessor(features)
  imputed <- apply_model_preprocessor(features, prep)
  expect_true(all(is.finite(imputed$log_debt_ratio)))
})
