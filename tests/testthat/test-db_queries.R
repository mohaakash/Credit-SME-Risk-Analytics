# Unit Tests: SQLite Database Queries

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
source(file.path(root, "R", "db_queries.R"))

test_that("SQLite query engine executes parameterized queries correctly", {
  sqlite_path <- file.path(root, "data", "processed", "give_me_some_credit.sqlite")
  con <- db_connect(sqlite_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  expect_true(DBI::dbIsValid(con))
  
  # 1. Portfolio KPIs
  kpis <- db_get_portfolio_kpis(con)
  expect_equal(nrow(kpis), 1)
  expect_equal(kpis$borrower_count, 150000)
  expect_true(kpis$default_rate > 0.05 && kpis$default_rate < 0.10)
  expect_true(kpis$mean_predicted_risk > 0.05 && kpis$mean_predicted_risk < 0.10)
  
  # Filtered KPIs
  kpis_filtered <- db_get_portfolio_kpis(con, age_band = "30-44", income_status = "Observed")
  expect_equal(nrow(kpis_filtered), 1)
  expect_true(kpis_filtered$borrower_count > 0 && kpis_filtered$borrower_count < 150000)
  
  # 2. Risk band counts
  bands <- db_get_risk_band_counts(con)
  expect_true(nrow(bands) >= 4)
  expect_equal(sum(bands$borrower_count), 150000)
  expect_setequal(bands$risk_band, c("Low", "Moderate", "High", "Very high"))
  
  # 3. Age default summary
  age_summary <- db_get_age_default_summary(con)
  expect_true(nrow(age_summary) >= 4)
  expect_true(all(age_summary$default_rate >= 0 & age_summary$default_rate <= 1))
  
  # 4. Segment summary across dimensions
  seg_vintage <- db_get_segment_summary(con, "vintage_quarter")
  expect_equal(nrow(seg_vintage), 8)
  expect_equal(sum(seg_vintage$borrower_count), 150000)
  
  seg_age <- db_get_segment_summary(con, "age_band")
  expect_true(nrow(seg_age) >= 4)
  
  # 5. Vintage performance
  v_perf <- db_get_vintage_performance(con)
  expect_equal(nrow(v_perf), 8)
  expect_equal(sum(v_perf$borrower_count), 150000)
  expect_true(all(v_perf$default_rate > 0.05 & v_perf$default_rate < 0.10))
  
  # 6. Filtered summary table
  tbl <- db_get_filtered_summary_table(con, age_band = "45-59")
  expect_true(nrow(tbl) > 0)
  expect_true(all(c("Risk band", "Borrowers", "Observed defaults", "Default rate", "Mean predicted risk") %in% names(tbl)))
})
