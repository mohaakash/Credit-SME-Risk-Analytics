# Reproducible descriptive and statistical analysis for the cleaned training data.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(readr)
})

wilson_interval <- function(successes, total, confidence = 0.95) {
  if (total == 0) {
    return(c(lower = NA_real_, upper = NA_real_))
  }

  z <- stats::qnorm(1 - (1 - confidence) / 2)
  proportion <- successes / total
  denominator <- 1 + z^2 / total
  centre <- (proportion + z^2 / (2 * total)) / denominator
  margin <- z * sqrt(
    proportion * (1 - proportion) / total + z^2 / (4 * total^2)
  ) / denominator

  c(lower = max(0, centre - margin), upper = min(1, centre + margin))
}

safe_t_test <- function(defaulted, non_defaulted) {
  result <- tryCatch(
    stats::t.test(defaulted, non_defaulted),
    error = function(error) NULL
  )

  if (is.null(result)) {
    return(c(
      mean_difference = NA_real_,
      mean_difference_ci_lower = NA_real_,
      mean_difference_ci_upper = NA_real_,
      welch_t_p_value = NA_real_
    ))
  }

  c(
    mean_difference = unname(result$estimate[[1]] - result$estimate[[2]]),
    mean_difference_ci_lower = unname(result$conf.int[[1]]),
    mean_difference_ci_upper = unname(result$conf.int[[2]]),
    welch_t_p_value = result$p.value
  )
}

safe_wilcoxon_p <- function(defaulted, non_defaulted) {
  if (length(unique(c(defaulted, non_defaulted))) < 2) {
    return(NA_real_)
  }

  tryCatch(
    stats::wilcox.test(defaulted, non_defaulted, exact = FALSE)$p.value,
    error = function(error) NA_real_
  )
}

numeric_group_comparison <- function(data, variable) {
  values <- data[[variable]]
  valid <- !is.na(values) & is.finite(values) & !is.na(data$serious_dlqin2yrs)
  defaulted <- values[valid & data$serious_dlqin2yrs == 1]
  non_defaulted <- values[valid & data$serious_dlqin2yrs == 0]
  t_test <- safe_t_test(defaulted, non_defaulted)

  tibble::tibble(
    variable = variable,
    n_nonmissing = length(defaulted) + length(non_defaulted),
    n_defaulted = length(defaulted),
    n_non_defaulted = length(non_defaulted),
    mean_defaulted = if (length(defaulted) > 0) mean(defaulted) else NA_real_,
    mean_non_defaulted = if (length(non_defaulted) > 0) mean(non_defaulted) else NA_real_,
    median_defaulted = if (length(defaulted) > 0) stats::median(defaulted) else NA_real_,
    median_non_defaulted = if (length(non_defaulted) > 0) stats::median(non_defaulted) else NA_real_,
    mean_difference = unname(t_test[["mean_difference"]]),
    mean_difference_ci_lower = unname(t_test[["mean_difference_ci_lower"]]),
    mean_difference_ci_upper = unname(t_test[["mean_difference_ci_upper"]]),
    welch_t_p_value = unname(t_test[["welch_t_p_value"]]),
    wilcoxon_p_value = safe_wilcoxon_p(defaulted, non_defaulted)
  )
}

segment_default_rates <- function(segment_name, bands, target) {
  bands <- as.character(bands)
  bands[is.na(bands)] <- "Missing"

  result <- tibble::tibble(
    segment = segment_name,
    band = bands,
    serious_dlqin2yrs = target
  ) |>
    dplyr::group_by(segment, band) |>
    dplyr::summarise(
      borrower_count = dplyr::n(),
      default_count = sum(serious_dlqin2yrs == 1),
      default_rate = mean(serious_dlqin2yrs),
      .groups = "drop"
    )

  intervals <- t(mapply(
    wilson_interval,
    result$default_count,
    result$borrower_count
  ))
  result$default_rate_ci_lower <- intervals[, "lower"]
  result$default_rate_ci_upper <- intervals[, "upper"]
  result
}

missingness_group_comparison <- function(data, variable) {
  values <- data[[variable]]
  missing <- is.na(values)
  missing_count <- sum(missing)
  observed_count <- sum(!missing)

  tibble::tibble(
    variable = variable,
    missing_count = missing_count,
    missing_pct = mean(missing),
    default_rate_missing = if (missing_count > 0) {
      mean(data$serious_dlqin2yrs[missing])
    } else {
      NA_real_
    },
    default_rate_observed = if (observed_count > 0) {
      mean(data$serious_dlqin2yrs[!missing])
    } else {
      NA_real_
    }
  ) |>
    dplyr::mutate(
      default_rate_difference = default_rate_missing - default_rate_observed
    )
}

delinquency_band <- function(values) {
  dplyr::case_when(
    is.na(values) ~ "Missing",
    values == 0 ~ "0",
    values <= 2 ~ "1-2",
    TRUE ~ "3+"
  )
}

markdown_table <- function(data) {
  if (nrow(data) == 0) {
    return(c("No rows."))
  }

  header <- paste0("| ", paste(names(data), collapse = " | "), " |")
  divider <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  rows <- apply(data, 1, function(row) {
    paste0("| ", paste(row, collapse = " | "), " |")
  })
  c(header, divider, rows)
}

format_number <- function(values, digits = 4) {
  ifelse(
    is.na(values),
    "NA",
    formatC(values, format = "f", digits = digits, big.mark = ",")
  )
}

format_percentage <- function(values, digits = 2) {
  ifelse(
    is.na(values),
    "NA",
    paste0(formatC(values * 100, format = "f", digits = digits), "%")
  )
}

format_p_value <- function(values) {
  ifelse(
    is.na(values),
    "NA",
    ifelse(
      values < 1e-6,
      "<1e-6",
      formatC(values, format = "f", digits = 6)
    )
  )
}

pretty_variable_labels <- c(
  revolving_utilization_of_unsecured_lines = "Revolving utilization",
  age = "Age",
  number_of_time30_59days_past_due_not_worse = "30-59 days late",
  debt_ratio = "Debt ratio",
  monthly_income = "Monthly income",
  number_of_open_credit_lines_and_loans = "Open credit lines",
  number_of_times90days_late = "90+ days late",
  number_real_estate_loans_or_lines = "Real-estate loans",
  number_of_time60_89days_past_due_not_worse = "60-89 days late",
  number_of_dependents = "Dependents"
)

run_statistical_analysis <- function(project_root = getwd()) {
  sqlite_path <- file.path(
    project_root,
    "data",
    "processed",
    "give_me_some_credit.sqlite"
  )
  generated_dir <- file.path(project_root, "reports", "generated")
  report_path <- file.path(project_root, "reports", "statistical-analysis-report.md")

  if (!file.exists(sqlite_path)) {
    stop(
      "Clean SQLite database not found. Run R/data_cleaning.R first: ",
      sqlite_path,
      call. = FALSE
    )
  }
  dir.create(generated_dir, recursive = TRUE, showWarnings = FALSE)

  connection <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  data <- DBI::dbReadTable(connection, "training_clean")
  missingness <- DBI::dbReadTable(connection, "missingness")

  numeric_variables <- c(
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
  required_columns <- c("serious_dlqin2yrs", numeric_variables)
  missing_columns <- setdiff(required_columns, names(data))
  if (length(missing_columns) > 0) {
    stop(
      "Cleaned table is missing required columns: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  data <- data[data$serious_dlqin2yrs %in% c(0, 1), , drop = FALSE]
  target <- as.numeric(data$serious_dlqin2yrs)

  numeric_comparisons <- dplyr::bind_rows(
    lapply(numeric_variables, function(variable) {
      numeric_group_comparison(data, variable)
    })
  )

  age_band <- cut(
    data$age,
    breaks = c(-Inf, 29, 44, 59, Inf),
    labels = c("<30", "30-44", "45-59", "60+"),
    right = TRUE
  )
  utilization_band <- cut(
    data$revolving_utilization_of_unsecured_lines,
    breaks = c(-Inf, 0.25, 0.5, 1, 2, Inf),
    labels = c("<=0.25", "0.25-0.50", "0.50-1.00", "1.00-2.00", ">2.00"),
    right = TRUE
  )
  debt_ratio_band <- dplyr::case_when(
    is.na(data$monthly_income) ~ "Missing income",
    data$debt_ratio <= 0.2 ~ "<=0.20",
    data$debt_ratio <= 0.5 ~ "0.20-0.50",
    data$debt_ratio <= 1.0 ~ "0.50-1.00",
    data$debt_ratio <= 10.0 ~ "1.00-10.00",
    TRUE ~ ">10.00"
  )
  income_band <- dplyr::case_when(
    is.na(data$monthly_income) ~ "Missing",
    data$monthly_income <= 2000 ~ "<=2,000",
    data$monthly_income <= 4000 ~ "2,001-4,000",
    data$monthly_income <= 8000 ~ "4,001-8,000",
    TRUE ~ ">8,000"
  )
  dependents_band <- dplyr::case_when(
    is.na(data$number_of_dependents) ~ "Missing",
    data$number_of_dependents == 0 ~ "0",
    data$number_of_dependents == 1 ~ "1",
    TRUE ~ "2+"
  )
  open_lines_band <- dplyr::case_when(
    is.na(data$number_of_open_credit_lines_and_loans) ~ "Missing",
    data$number_of_open_credit_lines_and_loans <= 4 ~ "0-4",
    data$number_of_open_credit_lines_and_loans <= 9 ~ "5-9",
    data$number_of_open_credit_lines_and_loans <= 19 ~ "10-19",
    TRUE ~ "20+"
  )
  real_estate_band <- dplyr::case_when(
    is.na(data$number_real_estate_loans_or_lines) ~ "Missing",
    data$number_real_estate_loans_or_lines == 0 ~ "0",
    data$number_real_estate_loans_or_lines == 1 ~ "1",
    TRUE ~ "2+"
  )

  band_definitions <- list(
    age_band = age_band,
    utilization_band = utilization_band,
    debt_ratio_band = debt_ratio_band,
    income_band = income_band,
    dependents_band = dependents_band,
    open_lines_band = open_lines_band,
    real_estate_band = real_estate_band,
    time_30_59_band = delinquency_band(
      data$number_of_time30_59days_past_due_not_worse
    ),
    time_60_89_band = delinquency_band(
      data$number_of_time60_89days_past_due_not_worse
    ),
    time_90_band = delinquency_band(data$number_of_times90days_late)
  )
  segment_rates <- dplyr::bind_rows(
    lapply(names(band_definitions), function(segment_name) {
      segment_default_rates(segment_name, band_definitions[[segment_name]], target)
    })
  )

  chi_square_tests <- dplyr::bind_rows(
    lapply(names(band_definitions), function(segment_name) {
      table_data <- table(band_definitions[[segment_name]], target)
      test <- tryCatch(
        suppressWarnings(stats::chisq.test(table_data, correct = FALSE)),
        error = function(error) NULL
      )
      if (is.null(test)) {
        return(tibble::tibble(
          segment = segment_name,
          chi_square_statistic = NA_real_,
          degrees_of_freedom = NA_real_,
          p_value = NA_real_,
          minimum_expected_count = NA_real_,
          assumption_warning = "Test could not be computed"
        ))
      }
      tibble::tibble(
        segment = segment_name,
        chi_square_statistic = unname(test$statistic),
        degrees_of_freedom = unname(test$parameter),
        p_value = test$p.value,
        minimum_expected_count = min(test$expected),
        assumption_warning = if (min(test$expected) < 5) {
          "Some expected counts are below 5"
        } else {
          "None"
        }
      )
    })
  )

  missingness_comparisons <- dplyr::bind_rows(
    lapply(numeric_variables, function(variable) {
      missingness_group_comparison(data, variable)
    })
  )

  correlation_matrix <- stats::cor(
    data[numeric_variables],
    use = "pairwise.complete.obs",
    method = "spearman"
  )

  model_data <- data.frame(
    serious_dlqin2yrs = target,
    age = data$age,
    log_revolving_utilization = log1p(pmax(
      data$revolving_utilization_of_unsecured_lines,
      0
    )),
    log_debt_ratio = log1p(pmin(pmax(data$debt_ratio, 0), 10)),
    log_monthly_income = log1p(pmax(data$monthly_income, 0)),
    open_credit_lines = data$number_of_open_credit_lines_and_loans,
    times_30_59 = data$number_of_time30_59days_past_due_not_worse,
    times_60_89 = data$number_of_time60_89days_past_due_not_worse,
    times_90 = data$number_of_times90days_late,
    real_estate_loans = data$number_real_estate_loans_or_lines,
    dependents = data$number_of_dependents
  )
  model_data <- model_data[stats::complete.cases(model_data), , drop = FALSE]

  initial_logistic_model <- stats::glm(
    serious_dlqin2yrs ~ age + log_revolving_utilization + log_debt_ratio +
      log_monthly_income + open_credit_lines + times_30_59 + times_60_89 +
      times_90 + real_estate_loans + dependents,
    data = model_data,
    family = stats::binomial()
  )
  model_summary <- summary(initial_logistic_model)
  coefficients <- as.data.frame(model_summary$coefficients)
  coefficients$term <- rownames(coefficients)
  rownames(coefficients) <- NULL
  names(coefficients)[1:4] <- c("estimate", "std_error", "z_value", "p_value")
  coefficients <- coefficients |>
    dplyr::select(term, estimate, std_error, z_value, p_value) |>
    dplyr::mutate(
      odds_ratio = exp(estimate),
      odds_ratio_ci_lower = exp(estimate - 1.96 * std_error),
      odds_ratio_ci_upper = exp(estimate + 1.96 * std_error)
    )

  readr::write_csv(
    numeric_comparisons,
    file.path(generated_dir, "numeric_group_comparisons.csv")
  )
  readr::write_csv(
    segment_rates,
    file.path(generated_dir, "segment_default_rates.csv")
  )
  readr::write_csv(
    chi_square_tests,
    file.path(generated_dir, "chi_square_tests.csv")
  )
  readr::write_csv(
    missingness_comparisons,
    file.path(generated_dir, "missingness_group_comparisons.csv")
  )
  readr::write_csv(
    as.data.frame(correlation_matrix) |>
      tibble::rownames_to_column("variable"),
    file.path(generated_dir, "correlation_matrix_spearman.csv")
  )
  readr::write_csv(
    coefficients,
    file.path(generated_dir, "initial_logistic_regression_terms.csv")
  )

  grDevices::png(
    file.path(generated_dir, "missingness.png"),
    width = 1400,
    height = 900,
    res = 120
  )
  plot_missingness <- missingness |>
    dplyr::filter(missing_count > 0) |>
    dplyr::arrange(missing_pct)
  graphics::par(mar = c(5, 12, 3, 2))
  graphics::barplot(
    plot_missingness$missing_pct * 100,
    names.arg = unname(pretty_variable_labels[plot_missingness$variable]),
    horiz = TRUE,
    las = 1,
    col = "#2f6690",
    xlab = "Missing rows (%)",
    main = paste0(
      "Source missingness after cleaning (n = ",
      formatC(nrow(data), format = "d", big.mark = ","),
      ")"
    )
  )
  grDevices::dev.off()

  age_rates <- segment_rates |>
    dplyr::filter(segment == "age_band")
  grDevices::png(
    file.path(generated_dir, "default_rate_by_age_band.png"),
    width = 1200,
    height = 800,
    res = 120
  )
  graphics::par(mar = c(6, 5, 3, 2))
  age_plot <- graphics::barplot(
    age_rates$default_rate * 100,
    names.arg = age_rates$band,
    col = "#3a7d44",
    ylim = c(0, max(age_rates$default_rate * 100) * 1.25),
    ylab = "Default rate (%)",
    xlab = "Age band",
    main = "Default rate by age band"
  )
  graphics::text(
    age_plot,
    age_rates$default_rate * 100,
    labels = paste0(
      formatC(age_rates$default_rate * 100, format = "f", digits = 1),
      "% (n=",
      formatC(age_rates$borrower_count, format = "d", big.mark = ","),
      ")"
    ),
    pos = 3,
    cex = 0.8
  )
  grDevices::dev.off()

  skewed_variables <- c(
    "revolving_utilization_of_unsecured_lines",
    "debt_ratio",
    "monthly_income"
  )
  grDevices::png(
    file.path(generated_dir, "numeric_distributions.png"),
    width = 1600,
    height = 1200,
    res = 120
  )
  graphics::par(mfrow = c(3, 4), mar = c(4, 4, 3, 1))
  for (variable in numeric_variables) {
    values <- data[[variable]]
    values <- values[is.finite(values)]
    transformed <- variable %in% skewed_variables
    plotted_values <- if (transformed) log1p(pmax(values, 0)) else values
    upper_limit <- stats::quantile(plotted_values, 0.99, names = FALSE, na.rm = TRUE)
    plotted_values <- plotted_values[plotted_values <= upper_limit]
    graphics::hist(
      plotted_values,
      breaks = 35,
      col = "#669bbc",
      border = "white",
      main = paste0(
        unname(pretty_variable_labels[variable]),
        "\n(n=",
        formatC(length(values), format = "d", big.mark = ","),
        ")"
      ),
      xlab = if (transformed) "log1p(value), <= 99th percentile" else "Value"
    )
  }
  graphics::plot.new()
  graphics::title("99th-percentile display cap")
  grDevices::dev.off()

  heatmap_matrix <- correlation_matrix[nrow(correlation_matrix):1, , drop = FALSE]
  heatmap_labels <- unname(pretty_variable_labels[colnames(correlation_matrix)])
  grDevices::png(
    file.path(generated_dir, "correlation_heatmap.png"),
    width = 1600,
    height = 1400,
    res = 120
  )
  graphics::par(mar = c(11, 12, 4, 2))
  palette <- grDevices::colorRampPalette(c("#2166ac", "white", "#b2182b"))(100)
  graphics::image(
    x = seq_len(ncol(correlation_matrix)),
    y = seq_len(nrow(correlation_matrix)),
    z = heatmap_matrix,
    col = palette,
    zlim = c(-1, 1),
    axes = FALSE,
    xlab = "",
    ylab = "",
    main = paste0(
      "Spearman correlation matrix\n(pairwise complete observations; n = ",
      formatC(nrow(data), format = "d", big.mark = ","),
      ")"
    )
  )
  graphics::axis(
    1,
    at = seq_len(ncol(correlation_matrix)),
    labels = heatmap_labels,
    las = 2,
    cex.axis = 0.7
  )
  graphics::axis(
    2,
    at = seq_len(nrow(correlation_matrix)),
    labels = rev(heatmap_labels),
    las = 2,
    cex.axis = 0.7
  )
  for (row in seq_len(nrow(heatmap_matrix))) {
    for (column in seq_len(ncol(heatmap_matrix))) {
      graphics::text(
        column,
        row,
        labels = formatC(heatmap_matrix[row, column], format = "f", digits = 2),
        cex = 0.55
      )
    }
  }
  grDevices::dev.off()

  segment_display <- segment_rates |>
    dplyr::filter(segment %in% c("age_band", "dependents_band", "income_band")) |>
    dplyr::mutate(
      borrower_count = formatC(borrower_count, format = "d", big.mark = ","),
      default_rate = paste0(formatC(default_rate * 100, format = "f", digits = 2), "%"),
      ci = paste0(
        formatC(default_rate_ci_lower * 100, format = "f", digits = 2), "% to ",
        formatC(default_rate_ci_upper * 100, format = "f", digits = 2), "%"
      )
    ) |>
    dplyr::select(segment, band, borrower_count, default_rate, ci)

  numeric_display <- numeric_comparisons |>
    dplyr::mutate(
      mean_defaulted = format_number(mean_defaulted),
      mean_non_defaulted = format_number(mean_non_defaulted),
      median_defaulted = format_number(median_defaulted),
      median_non_defaulted = format_number(median_non_defaulted),
      mean_difference = format_number(mean_difference),
      mean_difference_ci_lower = format_number(mean_difference_ci_lower),
      mean_difference_ci_upper = format_number(mean_difference_ci_upper),
      wilcoxon_p_value = format_p_value(wilcoxon_p_value)
    ) |>
    dplyr::select(
      variable,
      n_nonmissing,
      mean_defaulted,
      mean_non_defaulted,
      median_defaulted,
      median_non_defaulted,
      mean_difference,
      mean_difference_ci_lower,
      mean_difference_ci_upper,
      wilcoxon_p_value
    )

  chi_square_display <- chi_square_tests |>
    dplyr::mutate(
      chi_square_statistic = format_number(chi_square_statistic),
      p_value = format_p_value(p_value),
      minimum_expected_count = format_number(minimum_expected_count)
    )

  logistic_display <- coefficients |>
    dplyr::mutate(
      estimate = format_number(estimate),
      odds_ratio = format_number(odds_ratio),
      odds_ratio_ci_lower = format_number(odds_ratio_ci_lower),
      odds_ratio_ci_upper = format_number(odds_ratio_ci_upper),
      p_value = format_p_value(p_value)
    ) |>
    dplyr::select(term, estimate, odds_ratio, odds_ratio_ci_lower, odds_ratio_ci_upper, p_value)

  missing_display <- missingness_comparisons |>
    dplyr::mutate(
      missing_pct = format_percentage(missing_pct),
      default_rate_missing = format_percentage(default_rate_missing),
      default_rate_observed = format_percentage(default_rate_observed),
      default_rate_difference = ifelse(
        is.na(default_rate_difference),
        "NA",
        paste0(formatC(default_rate_difference * 100, format = "f", digits = 2), " pp")
      )
    ) |>
    dplyr::select(variable, missing_count, missing_pct, default_rate_missing, default_rate_observed, default_rate_difference)

  report_lines <- c(
    "# Statistical analysis report",
    "",
    "Generated by `R/statistical_analysis.R` from the current cleaned SQLite input.",
    "",
    "## Scope",
    "",
    "This report is generated by `R/statistical_analysis.R` from the cleaned `training_clean` SQLite table. It is a descriptive and exploratory Phase 2 analysis, not a lending-policy recommendation or production model validation.",
    "",
    paste0("The analysis includes ", formatC(nrow(data), format = "d", big.mark = ","), " valid target rows. The preliminary logistic regression uses ", formatC(nrow(model_data), format = "d", big.mark = ","), " complete cases and log1p transforms for highly skewed ratios and income."),
    "",
    "## Numeric comparisons by target",
    "",
    "The mean-difference interval is a Welch two-sample t-test interval for defaulted minus non-defaulted borrowers. The Wilcoxon p-value is included because several variables are strongly skewed. These are associations, not causal effects.",
    "",
    markdown_table(numeric_display),
    "",
    "## Segment default rates",
    "",
    "Rates include Wilson 95% confidence intervals. The displayed segments are descriptive groupings chosen for interpretability; they are not final risk bands.",
    "",
    markdown_table(segment_display),
    "",
    "## Missingness comparison",
    "",
    "Missing values are retained as source observations. Differences between missing and observed groups should be treated as data-quality signals, not evidence that missingness causes default.",
    "",
    markdown_table(missing_display),
    "",
    "## Chi-square tests",
    "",
    "Each test checks whether the binned segment and the binary target are independent. A small p-value indicates an association in this sample; it does not establish causality. Expected-count warnings identify where the chi-square approximation may be weak.",
    "",
    markdown_table(chi_square_display),
    "",
    "## Preliminary logistic-regression interpretation",
    "",
    "This screening model is included to support interpretation before the formal modeling phase. It uses complete cases, unweighted observations, and log1p-transformed revolving utilization, debt ratio, and monthly income. Odds ratios correspond to a one-unit increase in the displayed model term, not necessarily a one-unit increase in the original source variable.",
    "",
    paste0("Model converged: `", initial_logistic_model$converged, "`."),
    "",
    markdown_table(logistic_display),
    "",
    "## Generated artifacts",
    "",
    "- `reports/generated/numeric_group_comparisons.csv`",
    "- `reports/generated/segment_default_rates.csv`",
    "- `reports/generated/missingness_group_comparisons.csv`",
    "- `reports/generated/chi_square_tests.csv`",
    "- `reports/generated/correlation_matrix_spearman.csv`",
    "- `reports/generated/initial_logistic_regression_terms.csv`",
    "- `reports/generated/missingness.png`",
    "- `reports/generated/default_rate_by_age_band.png`",
    "- `reports/generated/numeric_distributions.png`",
    "- `reports/generated/correlation_heatmap.png`",
    "",
    "The next phase should use these findings to define a reproducible feature-engineering and held-out model-training plan."
  )
  writeLines(report_lines, report_path)

  message(glue::glue("Statistical analysis report written to {report_path}"))
  message(glue::glue("Generated {nrow(segment_rates)} segment summaries and {nrow(coefficients)} logistic terms"))

  invisible(list(
    numeric_comparisons = numeric_comparisons,
    segment_rates = segment_rates,
    missingness_comparisons = missingness_comparisons,
    chi_square_tests = chi_square_tests,
    correlation_matrix = correlation_matrix,
    coefficients = coefficients,
    report_path = report_path
  ))
}

if (sys.nframe() == 0) {
  run_statistical_analysis()
}
