# Reproducible import, cleaning, validation, and SQLite load for Give Me Some Credit.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(glue)
  library(janitor)
  library(readr)
  library(readxl)
  library(tidyr)
})

run_data_cleaning <- function(project_root = getwd()) {
  raw_training_path <- file.path(project_root, "data", "raw", "cs-training.csv")
  raw_dictionary_path <- file.path(project_root, "data", "raw", "Data Dictionary.xls")
  processed_dir <- file.path(project_root, "data", "processed")
  generated_report_dir <- file.path(project_root, "reports", "generated")

  if (!file.exists(raw_training_path)) {
    stop("Training data not found at: ", raw_training_path, call. = FALSE)
  }
  if (!file.exists(raw_dictionary_path)) {
    stop("Data dictionary not found at: ", raw_dictionary_path, call. = FALSE)
  }

  dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(generated_report_dir, recursive = TRUE, showWarnings = FALSE)

  raw <- readr::read_csv(
    raw_training_path,
    name_repair = "minimal",
    show_col_types = FALSE,
    na = c("", "NA")
  )
  names(raw)[1] <- "id"
  raw <- janitor::clean_names(raw)

  expected_columns <- c(
    "id",
    "serious_dlqin2yrs",
    "revolving_utilization_of_unsecured_lines",
    "age",
    "number_of_time30_59days_past_due_not_worse",
    "debt_ratio",
    "monthly_income",
    "number_of_open_credit_lines_and_loans",
    "number_of_times90days_late",
    "number_real_estate_loans_or_lines",
    "number_of_time60_89days_past_due_not_worse",
    "number_of_dependents"
  )
  if (!identical(names(raw), expected_columns)) {
    stop(
      "Unexpected training columns. Got: ",
      paste(names(raw), collapse = ", "),
      call. = FALSE
    )
  }

  dictionary <- readxl::read_excel(
    raw_dictionary_path,
    sheet = 1,
    col_names = TRUE,
    .name_repair = "minimal"
  )

  sentinel_columns <- c(
    "number_of_time30_59days_past_due_not_worse",
    "number_of_time60_89days_past_due_not_worse",
    "number_of_times90days_late"
  )

  cleaned <- raw

  for (column in sentinel_columns) {
    flag_name <- paste0(column, "_sentinel_96_98")
    cleaned[[flag_name]] <- cleaned[[column]] %in% c(96, 98)
    cleaned[[column]][cleaned[[column]] %in% c(96, 98)] <- NA
  }

  cleaned$age_zero_invalid <- cleaned$age == 0
  cleaned$age[cleaned$age == 0] <- NA

  cleaned$monthly_income_missing <- is.na(cleaned$monthly_income)
  cleaned$number_of_dependents_missing <- is.na(cleaned$number_of_dependents)
  cleaned$revolving_utilization_gt_1 <-
    cleaned$revolving_utilization_of_unsecured_lines > 1
  cleaned$debt_ratio_gt_10 <- cleaned$debt_ratio > 10
  cleaned$duplicate_id <- duplicated(cleaned$id) | duplicated(cleaned$id, fromLast = TRUE)
  cleaned$target_invalid <-
    is.na(cleaned$serious_dlqin2yrs) |
    !cleaned$serious_dlqin2yrs %in% c(0, 1)

  issue_flag_columns <- c(
    paste0(sentinel_columns, "_sentinel_96_98"),
    "age_zero_invalid",
    "monthly_income_missing",
    "number_of_dependents_missing",
    "revolving_utilization_gt_1",
    "debt_ratio_gt_10",
    "duplicate_id",
    "target_invalid"
  )
  cleaned$row_quality_issue_count <- rowSums(
    as.data.frame(cleaned[issue_flag_columns]),
    na.rm = TRUE
  )
  cleaned$row_quality_flag <- cleaned$row_quality_issue_count > 0

  base_columns <- expected_columns
  missingness <- tibble::tibble(
    variable = base_columns,
    missing_count = vapply(cleaned[base_columns], function(x) sum(is.na(x)), integer(1))
  ) |>
    dplyr::mutate(
      row_count = nrow(cleaned),
      missing_pct = missing_count / row_count
    )

  target_summary <- cleaned |>
    dplyr::count(serious_dlqin2yrs, name = "row_count") |>
    dplyr::mutate(rate = row_count / sum(row_count))

  quality_summary <- tibble::tibble(
    metric = c(
      "source_rows",
      "source_columns",
      "cleaned_rows",
      "cleaned_columns",
      "duplicate_ids",
      "invalid_target_rows",
      "age_zero_rows_replaced_with_missing",
      "rows_with_any_quality_flag",
      "sentinel_96_98_values_replaced_with_missing",
      "revolving_utilization_greater_than_one",
      "debt_ratio_greater_than_ten"
    ),
    value = c(
      nrow(raw),
      ncol(raw),
      nrow(cleaned),
      ncol(cleaned),
      sum(cleaned$duplicate_id),
      sum(cleaned$target_invalid),
      sum(cleaned$age_zero_invalid),
      sum(cleaned$row_quality_flag),
      sum(rowSums(as.data.frame(cleaned[paste0(sentinel_columns, "_sentinel_96_98")]))),
      sum(cleaned$revolving_utilization_gt_1, na.rm = TRUE),
      sum(cleaned$debt_ratio_gt_10, na.rm = TRUE)
    )
  )

  clean_csv_path <- file.path(processed_dir, "give_me_some_credit_train_clean.csv")
  sqlite_path <- file.path(processed_dir, "give_me_some_credit.sqlite")
  missingness_path <- file.path(generated_report_dir, "missingness.csv")
  quality_summary_path <- file.path(generated_report_dir, "quality_summary.csv")
  target_summary_path <- file.path(generated_report_dir, "target_summary.csv")
  report_path <- file.path(project_root, "reports", "data-quality-report.md")

  readr::write_csv(cleaned, clean_csv_path)
  readr::write_csv(missingness, missingness_path)
  readr::write_csv(quality_summary, quality_summary_path)
  readr::write_csv(target_summary, target_summary_path)

  connection <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  DBI::dbWriteTable(connection, "training_clean", cleaned, overwrite = TRUE)
  DBI::dbWriteTable(connection, "missingness", missingness, overwrite = TRUE)
  DBI::dbWriteTable(connection, "quality_summary", quality_summary, overwrite = TRUE)
  DBI::dbWriteTable(connection, "target_summary", target_summary, overwrite = TRUE)

  target_table <- paste0(
    "| ", target_summary$serious_dlqin2yrs,
    " | ", target_summary$row_count,
    " | ", sprintf("%.4f", target_summary$rate), " |"
  )
  missing_table <- missingness |>
    dplyr::filter(missing_count > 0) |>
    dplyr::mutate(row = paste0(
      "| `", variable, "` | ", missing_count,
      " | ", sprintf("%.4f", missing_pct), " |"
    )) |>
    dplyr::pull(row)

  report_lines <- c(
    "# Data-quality report",
    "",
    paste0("Generated: ", format(Sys.time(), tz = "UTC")),
    "",
    "## Scope",
    "",
    "This report covers the Kaggle Give Me Some Credit training file. It is generated by `R/data_cleaning.R` and is intended as a reproducible Phase 1 baseline.",
    "",
    "## Validation summary",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    paste0("| Source rows | ", nrow(raw), " |"),
    paste0("| Source columns | ", ncol(raw), " |"),
    paste0("| Cleaned rows | ", nrow(cleaned), " |"),
    paste0("| Cleaned columns | ", ncol(cleaned), " |"),
    paste0("| Duplicate IDs | ", sum(cleaned$duplicate_id), " |"),
    paste0("| Invalid target rows | ", sum(cleaned$target_invalid), " |"),
    paste0("| Rows with any quality flag | ", sum(cleaned$row_quality_flag), " |"),
    "",
    "## Target distribution",
    "",
    "| Target | Rows | Rate |",
    "| ---: | ---: | ---: |",
    target_table,
    "",
    "## Missing values after source import",
    "",
    "| Variable | Missing rows | Missing rate |",
    "| --- | ---: | ---: |",
    if (length(missing_table) > 0) missing_table else "| None | 0 | 0.0000 |",
    "",
    "## Cleaning decisions",
    "",
    "- The unnamed first source column is renamed `id`.",
    "- Source names are converted to snake_case.",
    "- Age `0` is treated as invalid and converted to missing.",
    "- Delinquency counts coded `96` or `98` are flagged and converted to missing; the flags remain in the cleaned file.",
    "- Missing income and dependents are retained and flagged for an explicit modeling treatment later.",
    "- Extreme revolving-utilization and debt-ratio values are flagged, not removed or winsorized.",
    "- Duplicate IDs and invalid target values are flagged so they cannot be hidden by downstream summaries.",
    "",
    "## Output artifacts",
    "",
    "- Cleaned CSV: `data/processed/give_me_some_credit_train_clean.csv`",
    "- SQLite database: `data/processed/give_me_some_credit.sqlite`",
    "- Missingness CSV: `reports/generated/missingness.csv`",
    "- Quality summary CSV: `reports/generated/quality_summary.csv`",
    "",
    "The cleaned CSV and SQLite database are ignored by Git and can be regenerated from the raw file."
  )
  writeLines(report_lines, report_path)

  message(glue::glue("Cleaned {nrow(cleaned)} rows into {clean_csv_path}"))
  message(glue::glue("SQLite database written to {sqlite_path}"))
  message(glue::glue("Data-quality report written to {report_path}"))

  invisible(list(
    cleaned = cleaned,
    dictionary = dictionary,
    missingness = missingness,
    quality_summary = quality_summary,
    target_summary = target_summary,
    report_path = report_path,
    sqlite_path = sqlite_path
  ))
}

run_data_cleaning()
