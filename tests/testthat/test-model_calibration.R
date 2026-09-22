# Unit Tests: Model Probability Calibration & Risk Scoring

test_that("Bayesian prior odds formula correctly reverses class weighting shift", {
  # Suppose class imbalance was weighted by w = 14 (neg/pos ratio)
  w <- 13.96
  
  # A borrower with average risk produces raw score p_raw = 0.50 under balanced training
  p_raw <- 0.50
  
  # Apply Bayesian adjustment:
  # odds_cal = (p_raw / (1 - p_raw)) / w = 1 / 13.96
  # p_cal = odds_cal / (1 + odds_cal) = (1 / 13.96) / (1 + 1 / 13.96) = 1 / 14.96 = 0.0668 (exact 6.7% prior!)
  raw_odds <- p_raw / (1 - p_raw)
  cal_odds <- raw_odds / w
  p_cal <- cal_odds / (1 + cal_odds)
  
  expect_equal(round(p_cal, 4), 0.0668)
  expect_true(p_cal > 0 && p_cal < 1)
})

test_that("Scorecard risk band cutoffs produce strictly monotonic risk ordering", {
  risk_score_quantiles <- c(p50 = 0.03881347, p80 = 0.06463351, p95 = 0.20574650)
  
  assign_risk_band <- function(score) {
    factor(
      dplyr::case_when(
        score <= risk_score_quantiles[["p50"]] ~ "Low",
        score <= risk_score_quantiles[["p80"]] ~ "Moderate",
        score <= risk_score_quantiles[["p95"]] ~ "High",
        TRUE ~ "Very high"
      ),
      levels = c("Low", "Moderate", "High", "Very high")
    )
  }
  
  test_scores <- c(0.01, 0.05, 0.12, 0.45)
  assigned_bands <- assign_risk_band(test_scores)
  
  expect_equal(as.character(assigned_bands), c("Low", "Moderate", "High", "Very high"))
  expect_true(as.numeric(assigned_bands[1]) < as.numeric(assigned_bands[2]))
  expect_true(as.numeric(assigned_bands[2]) < as.numeric(assigned_bands[3]))
  expect_true(as.numeric(assigned_bands[3]) < as.numeric(assigned_bands[4]))
})
