# Database query helpers for Consumer Credit Risk Dashboard.
# Executes parameterized SQL queries directly against SQLite.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
})

execute_query <- function(con, query, params = list()) {
  if (length(params) > 0) {
    DBI::dbGetQuery(con, query, params = params)
  } else {
    DBI::dbGetQuery(con, query)
  }
}

db_connect <- function(sqlite_path) {
  DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
}

db_get_portfolio_kpis <- function(con, age_band = "All", income_status = "All", delinquency_status = "All") {
  query <- "
    SELECT 
      COUNT(*) AS borrower_count,
      AVG(serious_dlqin2yrs) AS default_rate,
      AVG(predicted_risk) AS mean_predicted_risk,
      SUM(CASE WHEN risk_band IN ('High', 'Very high') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS high_risk_rate
    FROM training_clean
    WHERE 1=1
  "
  params <- list()
  if (!is.null(age_band) && age_band != "All") {
    query <- paste(query, "AND age_band = ?")
    params <- c(params, age_band)
  }
  if (!is.null(income_status) && income_status != "All") {
    query <- paste(query, "AND income_status = ?")
    params <- c(params, income_status)
  }
  if (!is.null(delinquency_status) && delinquency_status != "All") {
    query <- paste(query, "AND delinquency_90_status = ?")
    params <- c(params, delinquency_status)
  }
  
  execute_query(con, query, params)
}

db_get_risk_band_counts <- function(con, age_band = "All", income_status = "All", delinquency_status = "All") {
  query <- "
    SELECT 
      risk_band,
      COUNT(*) AS borrower_count
    FROM training_clean
    WHERE 1=1
  "
  params <- list()
  if (!is.null(age_band) && age_band != "All") {
    query <- paste(query, "AND age_band = ?")
    params <- c(params, age_band)
  }
  if (!is.null(income_status) && income_status != "All") {
    query <- paste(query, "AND income_status = ?")
    params <- c(params, income_status)
  }
  if (!is.null(delinquency_status) && delinquency_status != "All") {
    query <- paste(query, "AND delinquency_90_status = ?")
    params <- c(params, delinquency_status)
  }
  query <- paste(query, "GROUP BY risk_band ORDER BY risk_band")
  
  execute_query(con, query, params)
}

db_get_age_default_summary <- function(con, income_status = "All", delinquency_status = "All") {
  query <- "
    SELECT 
      age_band,
      COUNT(*) AS borrower_count,
      AVG(serious_dlqin2yrs) AS default_rate
    FROM training_clean
    WHERE 1=1
  "
  params <- list()
  if (!is.null(income_status) && income_status != "All") {
    query <- paste(query, "AND income_status = ?")
    params <- c(params, income_status)
  }
  if (!is.null(delinquency_status) && delinquency_status != "All") {
    query <- paste(query, "AND delinquency_90_status = ?")
    params <- c(params, delinquency_status)
  }
  query <- paste(query, "GROUP BY age_band ORDER BY age_band")
  
  execute_query(con, query, params)
}

db_get_segment_summary <- function(con, group_column) {
  valid_columns <- c("age_band", "income_status", "delinquency_90_status", "risk_band", "vintage_quarter")
  if (!group_column %in% valid_columns) {
    stop("Invalid segment column for SQL query: ", group_column, call. = FALSE)
  }
  
  query <- sprintf("
    SELECT 
      %s AS band,
      COUNT(*) AS borrower_count,
      SUM(serious_dlqin2yrs) AS default_count,
      AVG(serious_dlqin2yrs) AS default_rate,
      AVG(predicted_risk) AS mean_predicted_risk
    FROM training_clean
    GROUP BY %s
    ORDER BY %s
  ", group_column, group_column, group_column)
  
  DBI::dbGetQuery(con, query)
}

db_get_vintage_performance <- function(con) {
  query <- "
    SELECT 
      vintage_quarter,
      COUNT(*) AS borrower_count,
      SUM(serious_dlqin2yrs) AS default_count,
      AVG(serious_dlqin2yrs) AS default_rate,
      AVG(revolving_utilization_of_unsecured_lines) AS mean_utilization,
      AVG(predicted_risk) AS mean_predicted_risk
    FROM training_clean
    GROUP BY vintage_quarter
    ORDER BY vintage_quarter
  "
  DBI::dbGetQuery(con, query)
}

db_get_filtered_summary_table <- function(con, age_band = "All", income_status = "All", delinquency_status = "All") {
  query <- "
    SELECT 
      risk_band AS `Risk band`,
      COUNT(*) AS `Borrowers`,
      SUM(serious_dlqin2yrs) AS `Observed defaults`,
      AVG(serious_dlqin2yrs) AS `Default rate`,
      AVG(predicted_risk) AS `Mean predicted risk`
    FROM training_clean
    WHERE 1=1
  "
  params <- list()
  if (!is.null(age_band) && age_band != "All") {
    query <- paste(query, "AND age_band = ?")
    params <- c(params, age_band)
  }
  if (!is.null(income_status) && income_status != "All") {
    query <- paste(query, "AND income_status = ?")
    params <- c(params, income_status)
  }
  if (!is.null(delinquency_status) && delinquency_status != "All") {
    query <- paste(query, "AND delinquency_90_status = ?")
    params <- c(params, delinquency_status)
  }
  query <- paste(query, "GROUP BY risk_band ORDER BY risk_band")
  
  execute_query(con, query, params)
}
