# Consumer Credit Risk Analytics & Scorecard Monitoring Dashboard
# Modularized Architecture with bslib, ggplot2, DT, and Shiny Modules

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(readr)
  library(shiny)
  library(bslib)
  library(DT)
  library(ggplot2)
  library(scales)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
sqlite_path <- file.path(project_root, "data", "processed", "give_me_some_credit.sqlite")
required_artifacts <- c(
  sqlite_path,
  file.path(project_root, "models", "logistic_model.rds"),
  file.path(project_root, "models", "model_preprocessor.rds"),
  file.path(project_root, "reports", "generated", "model_metrics.csv"),
  file.path(project_root, "reports", "generated", "model_calibration.csv"),
  file.path(project_root, "reports", "generated", "model_lift_by_decile.csv"),
  file.path(project_root, "reports", "generated", "model_threshold_metrics.csv"),
  file.path(project_root, "reports", "generated", "model_roc_curves.csv"),
  file.path(project_root, "reports", "generated", "numeric_group_comparisons.csv"),
  file.path(project_root, "reports", "generated", "missingness.csv"),
  file.path(project_root, "reports", "generated", "segment_default_rates.csv"),
  file.path(project_root, "reports", "generated", "correlation_matrix_spearman.csv"),
  file.path(project_root, "reports", "generated", "monitoring_summary.csv"),
  file.path(project_root, "reports", "generated", "monitoring_distributions.csv"),
  file.path(project_root, "reports", "generated", "monitoring_psi.csv"),
  file.path(project_root, "reports", "generated", "monitoring_psi_trends.csv"),
  file.path(project_root, "reports", "generated", "monitoring_feature_drift.csv"),
  file.path(project_root, "reports", "generated", "monitoring_calibration.csv")
)
missing_artifacts <- required_artifacts[!file.exists(required_artifacts)]
if (length(missing_artifacts) > 0) {
  stop(
    "Dashboard artifacts are missing. Run pipelines first. Missing: ",
    paste(missing_artifacts, collapse = ", "),
    call. = FALSE
  )
}

# Source Core Helpers & Query Engines
source(file.path(project_root, "R", "ui_helpers.R"))
source(file.path(project_root, "R", "feature_engineering.R"))
source(file.path(project_root, "R", "db_queries.R"))

# Source Modular Components
source(file.path(project_root, "R", "mod_overview.R"))
source(file.path(project_root, "R", "mod_portfolio.R"))
source(file.path(project_root, "R", "mod_statistics.R"))
source(file.path(project_root, "R", "mod_models.R"))
source(file.path(project_root, "R", "mod_monitoring.R"))
source(file.path(project_root, "R", "mod_simulator.R"))

# Initialize SQLite Connection
db_connection <- db_connect(sqlite_path)

# Load CSV & Model Artifacts
model_metrics <- readr::read_csv(file.path(project_root, "reports", "generated", "model_metrics.csv"), show_col_types = FALSE)
model_calibration <- readr::read_csv(file.path(project_root, "reports", "generated", "model_calibration.csv"), show_col_types = FALSE)
model_lift <- readr::read_csv(file.path(project_root, "reports", "generated", "model_lift_by_decile.csv"), show_col_types = FALSE)
model_thresholds <- readr::read_csv(file.path(project_root, "reports", "generated", "model_threshold_metrics.csv"), show_col_types = FALSE)
model_roc_curves <- readr::read_csv(file.path(project_root, "reports", "generated", "model_roc_curves.csv"), show_col_types = FALSE)
numeric_comparisons <- readr::read_csv(file.path(project_root, "reports", "generated", "numeric_group_comparisons.csv"), show_col_types = FALSE)
missingness <- readr::read_csv(file.path(project_root, "reports", "generated", "missingness.csv"), show_col_types = FALSE)
segment_rates <- readr::read_csv(file.path(project_root, "reports", "generated", "segment_default_rates.csv"), show_col_types = FALSE)
correlation_data <- readr::read_csv(file.path(project_root, "reports", "generated", "correlation_matrix_spearman.csv"), show_col_types = FALSE)
monitoring_summary <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_summary.csv"), show_col_types = FALSE)
monitoring_distributions <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_distributions.csv"), show_col_types = FALSE)
monitoring_psi <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_psi.csv"), show_col_types = FALSE)
monitoring_psi_trends <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_psi_trends.csv"), show_col_types = FALSE)
monitoring_feature_drift <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_feature_drift.csv"), show_col_types = FALSE)
monitoring_calibration <- readr::read_csv(file.path(project_root, "reports", "generated", "monitoring_calibration.csv"), show_col_types = FALSE)

logistic_model <- readRDS(file.path(project_root, "models", "logistic_model.rds"))
model_preprocessor <- readRDS(file.path(project_root, "models", "model_preprocessor.rds"))

# Reference Quantiles for Scorecard Risk Tiers
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

# Presentation Mappings
pretty_feature_labels <- c(
  age = "Age", log_revolving_utilization = "Revolving utilization", log_debt_ratio = "Debt ratio",
  log_monthly_income = "Monthly income", open_credit_lines = "Open credit lines", times_30_59 = "30-59 days late",
  times_60_89 = "60-89 days late", times_90 = "90+ days late", real_estate_loans = "Real-estate loans",
  dependents = "Dependents", age_missing = "Age missing", monthly_income_missing = "Monthly income missing",
  dependents_missing = "Dependents missing", time_30_59_missing = "30-59-day history missing",
  time_60_89_missing = "60-89-day history missing", time_90_missing = "90-day history missing",
  revolving_utilization_gt_1 = "Utilization above 1", debt_ratio_gt_10 = "Debt ratio above 10"
)

model_display_labels <- c(
  Logistic = "Logistic Baseline",
  Logistic_WOE = "WoE Logistic Scorecard",
  CART = "Decision Tree (CART)",
  RandomForest = "Random Forest (Calibrated)",
  XGBoost = "XGBoost (Calibrated)"
)

stat_distribution_variables <- c(
  "Age" = "age", "Monthly income" = "monthly_income", "Debt ratio" = "debt_ratio",
  "Revolving utilization" = "revolving_utilization_of_unsecured_lines",
  "Open credit lines" = "number_of_open_credit_lines_and_loans",
  "30-59 days late" = "number_of_time30_59days_past_due_not_worse",
  "60-89 days late" = "number_of_time60_89days_past_due_not_worse",
  "90+ days late" = "number_of_times90days_late",
  "Dependents" = "number_of_dependents"
)

monitoring_feature_labels <- c(
  age = "Age", monthly_income = "Monthly income", debt_ratio = "Debt ratio",
  revolving_utilization_of_unsecured_lines = "Revolving utilization",
  number_of_open_credit_lines_and_loans = "Open credit lines",
  number_of_time30_59days_past_due_not_worse = "30-59 days late",
  number_of_time60_89days_past_due_not_worse = "60-89 days late",
  number_of_times90days_late = "90+ days late",
  number_real_estate_loans_or_lines = "Real-estate loans",
  number_of_dependents = "Dependents"
)

app_css <- "
  body { background-color: #F8FAFC; color: #1E293B; }
  .navbar { box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.08); border-bottom: 1px solid #E2E8F0; }
  .navbar-brand { font-size: 1.15rem; letter-spacing: -0.02em; }
  .card { border: 1px solid #E2E8F0; border-radius: 10px; box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.04); background-color: #FFFFFF; margin-bottom: 1.25rem; }
  .card-header { background-color: #FAFAFA; border-bottom: 1px solid #E2E8F0; font-weight: 600; padding: 0.85rem 1.25rem; }
  .text-teal { color: #197682 !important; }
  .tracking-wider { letter-spacing: 0.05em; }
  .bslib-value-box { border-radius: 10px; box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.05); border: 1px solid rgba(0, 0, 0, 0.05); }
  .risk-result { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .risk-box { padding: 20px; border-radius: 10px; border: 1px solid; }
  .risk-score-box { background-color: #EAF6F7; border-color: #BEE3E8; color: #197682; }
  .risk-band-box { background-color: #EDF4FF; border-color: #CFE0FC; color: #2563EB; }
  .risk-box .risk-val { font-size: 2.2rem; font-weight: 700; line-height: 1.1; margin: 6px 0; }
  .dataTables_wrapper .dataTables_paginate .paginate_button { padding: 2px 8px !important; }
  .dataTables_wrapper .dataTables_filter input { border: 1px solid #CBD5E1; border-radius: 6px; padding: 3px 8px; }
"

theme <- bslib::bs_theme(
  version = 5,
  preset = "bootstrap",
  primary = "#197682",
  secondary = "#4388E8",
  success = "#2E7D32",
  warning = "#D97706",
  danger = "#DC2626",
  base_font = bslib::font_collection("-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif")
)

ui <- bslib::page_navbar(
  title = tags$span(
    icon("shield-halved", class = "text-teal me-2"),
    tags$strong("Consumer Credit Risk"),
    tags$span(class = "badge ms-2 text-white", style = "font-size: 11px; background-color: #197682;", "Scorecard Engine")
  ),
  id = "main_nav",
  theme = theme,
  fillable = FALSE,
  header = tags$head(tags$style(HTML(app_css))),
  
  bslib::nav_panel(title = "Dashboard", icon = icon("gauge-high"), mod_overview_ui("overview")),
  bslib::nav_panel(title = "Portfolio Performance", icon = icon("chart-column"), mod_portfolio_ui("portfolio")),
  bslib::nav_panel(title = "Statistical Analysis", icon = icon("chart-line"), mod_statistics_ui("statistics", stat_distribution_variables)),
  bslib::nav_panel(title = "Credit Model", icon = icon("calculator"), mod_models_ui("models")),
  bslib::nav_panel(title = "Monitoring", icon = icon("shield-halved"), mod_monitoring_ui("monitoring")),
  bslib::nav_panel(title = "Risk Simulator", icon = icon("user-shield"), mod_simulator_ui("simulator"))
)

server <- function(input, output, session) {
  mod_overview_server("overview", db_connection)
  mod_portfolio_server("portfolio", db_connection)
  mod_statistics_server("statistics", db_connection, missingness, correlation_data, numeric_comparisons, segment_rates, stat_distribution_variables, pretty_feature_labels)
  mod_models_server("models", model_metrics, model_calibration, model_lift, model_thresholds, model_roc_curves, model_display_labels)
  mod_monitoring_server("monitoring", monitoring_summary, monitoring_psi, monitoring_psi_trends, monitoring_feature_drift, monitoring_calibration, monitoring_feature_labels)
  mod_simulator_server("simulator", logistic_model, model_preprocessor, assign_risk_band, pretty_feature_labels)
}

shiny::onStop(function() {
  if (DBI::dbIsValid(db_connection)) {
    DBI::dbDisconnect(db_connection)
  }
})

shinyApp(ui, server)
