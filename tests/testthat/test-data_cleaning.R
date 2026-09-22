# Unit Tests: Data Cleaning Pipeline

get_project_root <- function() {
  candidates <- c(".", "../..", "../../..")
  for (cand in candidates) {
    if (file.exists(file.path(cand, "data", "processed", "give_me_some_credit.sqlite"))) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  stop("Could not locate project root directory.")
}

test_that("data cleaning pipeline produces valid cleaned SQLite table", {
  root <- get_project_root()
  sqlite_path <- file.path(root, "data", "processed", "give_me_some_credit.sqlite")
  expect_true(file.exists(sqlite_path))
  
  con <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  
  # Check row count
  count_df <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM training_clean")
  expect_equal(count_df$n, 150000)
  
  # Check vintage quarters
  vintages <- DBI::dbGetQuery(con, "SELECT DISTINCT vintage_quarter FROM training_clean ORDER BY vintage_quarter")$vintage_quarter
  expected_vintages <- c("2022Q1", "2022Q2", "2022Q3", "2022Q4", "2023Q1", "2023Q2", "2023Q3", "2023Q4")
  expect_equal(vintages, expected_vintages)
  
  # Check target column is binary (0 or 1)
  target_vals <- DBI::dbGetQuery(con, "SELECT DISTINCT serious_dlqin2yrs FROM training_clean")$serious_dlqin2yrs
  expect_setequal(target_vals, c(0, 1))
  
  # Check delinquency sentinel replacements
  sentinel_check <- DBI::dbGetQuery(con, "
    SELECT 
      SUM(CASE WHEN number_of_time30_59days_past_due_not_worse IN (96, 98) THEN 1 ELSE 0 END) AS cnt_30_59,
      SUM(CASE WHEN number_of_time60_89days_past_due_not_worse IN (96, 98) THEN 1 ELSE 0 END) AS cnt_60_89,
      SUM(CASE WHEN number_of_times90days_late IN (96, 98) THEN 1 ELSE 0 END) AS cnt_90
    FROM training_clean
  ")
  expect_equal(sentinel_check$cnt_30_59, 0)
  expect_equal(sentinel_check$cnt_60_89, 0)
  expect_equal(sentinel_check$cnt_90, 0)
  
  # Check missing income indicator alignment
  income_missing_check <- DBI::dbGetQuery(con, "
    SELECT 
      SUM(CASE WHEN monthly_income IS NULL AND monthly_income_missing = 0 THEN 1 ELSE 0 END) AS invalid_missing,
      SUM(CASE WHEN monthly_income IS NOT NULL AND monthly_income_missing = 1 THEN 1 ELSE 0 END) AS invalid_observed
    FROM training_clean
  ")
  expect_equal(income_missing_check$invalid_missing, 0)
  expect_equal(income_missing_check$invalid_observed, 0)
})
