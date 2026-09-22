# Module: Statistical Analysis & Feature Diagnostics
# Handles distribution exploration, missingness, correlation heatmap, Wilcoxon tests, and Wilson CIs.

mod_statistics_ui <- function(id, stat_distribution_variables) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Exploratory Analysis",
      "Feature Diagnostics & Independence",
      "Non-parametric distribution comparisons, missingness profiles, rank correlation heatmaps, and Wilson 95% confidence intervals."
    ),
    bslib::card(
      bslib::card_header(icon("magnifying-glass-chart", class = "me-2 text-teal"), "Feature Distribution Explorer"),
      bslib::card_body(
        div(
          style = "max-width: 400px;",
          selectInput(ns("stat_distribution_variable"), "Select Feature to Compare", choices = stat_distribution_variables)
        ),
        plotOutput(ns("stat_distribution"), height = "360px")
      ),
      full_screen = TRUE
    ),
    div(
      class = "row g-3",
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Feature Missingness"),
          bslib::card_body(plotOutput(ns("stat_missingness"), height = "360px")),
          full_screen = TRUE
        )
      ),
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Spearman Rank Correlation Heatmap"),
          bslib::card_body(plotOutput(ns("stat_correlation"), height = "360px")),
          full_screen = TRUE
        )
      )
    ),
    bslib::card(
      bslib::card_header("Defaulted vs. Non-Defaulted Borrower Comparisons (Wilcoxon Rank-Sum Tests)"),
      bslib::card_body(DT::DTOutput(ns("stat_numeric_table"))),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Selected Segment Confidence Intervals (Wilson 95% Method)"),
      bslib::card_body(DT::DTOutput(ns("stat_segment_table"))),
      full_screen = TRUE
    )
  )
}

mod_statistics_server <- function(id, db_connection, missingness, correlation_data, numeric_comparisons, segment_rates, stat_distribution_variables, pretty_feature_labels) {
  moduleServer(id, function(input, output, session) {
    
    output$stat_distribution <- renderPlot({
      variable <- input$stat_distribution_variable
      if (is.null(variable) || !variable %in% unname(stat_distribution_variables)) {
        variable <- unname(stat_distribution_variables[[1]])
      }
      label <- names(stat_distribution_variables)[match(variable, stat_distribution_variables)]
      query <- sprintf("SELECT serious_dlqin2yrs, %s FROM training_clean WHERE %s IS NOT NULL", variable, variable)
      dist_data <- DBI::dbGetQuery(db_connection, query)
      dist_data <- dist_data[is.finite(dist_data[[variable]]) & !is.na(dist_data$serious_dlqin2yrs), , drop = FALSE]
      if (nrow(dist_data) == 0) return(NULL)
      
      dist_data$group <- factor(
        ifelse(dist_data$serious_dlqin2yrs == 1, "Defaulted", "Non-defaulted"),
        levels = c("Non-defaulted", "Defaulted")
      )
      
      q99 <- stats::quantile(dist_data[[variable]], 0.99, na.rm = TRUE)
      q01 <- stats::quantile(dist_data[[variable]], 0.01, na.rm = TRUE)
      
      ggplot2::ggplot(dist_data, ggplot2::aes(x = group, y = .data[[variable]], fill = group)) +
        ggplot2::geom_boxplot(width = 0.45, outlier.alpha = 0.1, outlier.size = 0.8, show.legend = FALSE) +
        ggplot2::scale_fill_manual(values = c("Non-defaulted" = "#91C3CB", "Defaulted" = "#E66B78")) +
        ggplot2::coord_cartesian(ylim = c(max(0, q01 * 0.9), q99 * 1.15)) +
        ggplot2::labs(
          title = paste("Distribution of", label, "by Default Status"),
          subtitle = paste0("Trimmed at 99th percentile for display clarity | Non-missing N = ", scales::comma(nrow(dist_data))),
          x = NULL,
          y = label
        ) +
        theme_dashboard()
    }, res = 110)

    output$stat_missingness <- renderPlot({
      values <- missingness |>
        dplyr::filter(missing_count > 0) |>
        dplyr::arrange(missing_pct)
      if (nrow(values) == 0) return(NULL)
      labels <- c(
        monthly_income = "Monthly income",
        number_of_dependents = "Dependents",
        number_of_time30_59days_past_due_not_worse = "30-59 days late",
        number_of_times90days_late = "90+ days late",
        number_of_time60_89days_past_due_not_worse = "60-89 days late",
        age = "Age"
      )
      values$feature_label <- unname(labels[values$variable])
      values$feature_label <- factor(values$feature_label, levels = values$feature_label)
      
      ggplot2::ggplot(values, ggplot2::aes(x = missing_pct, y = feature_label)) +
        ggplot2::geom_col(fill = "#E3AF3E", width = 0.5) +
        ggplot2::geom_text(
          ggplot2::aes(label = scales::percent(missing_pct, accuracy = 0.1)),
          hjust = -0.15,
          size = 3.6,
          fontface = "bold",
          color = "#374151"
        ) +
        ggplot2::scale_x_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.2))) +
        ggplot2::labs(
          title = "Feature Missingness Rates",
          subtitle = "Source fields requiring imputation or missingness flags",
          x = "Missing Share",
          y = NULL
        ) +
        theme_dashboard()
    }, res = 110)

    output$stat_correlation <- renderPlot({
      matrix <- as.matrix(correlation_data[, -1])
      rownames(matrix) <- correlation_data$variable
      col_labels <- unname(pretty_feature_labels[colnames(matrix)])
      row_labels <- unname(pretty_feature_labels[rownames(matrix)])
      
      corr_df <- expand.grid(
        row = seq_len(nrow(matrix)),
        col = seq_len(ncol(matrix))
      )
      corr_df$cor <- matrix[cbind(corr_df$row, corr_df$col)]
      corr_df$row_name <- factor(row_labels[corr_df$row], levels = rev(row_labels))
      corr_df$col_name <- factor(col_labels[corr_df$col], levels = col_labels)
      
      ggplot2::ggplot(corr_df, ggplot2::aes(x = col_name, y = row_name, fill = cor)) +
        ggplot2::geom_tile(color = "white", linewidth = 0.5) +
        ggplot2::geom_text(
          ggplot2::aes(label = sprintf("%.2f", cor)),
          size = 2.8,
          color = ifelse(abs(corr_df$cor) > 0.5, "white", "#1F2937")
        ) +
        ggplot2::scale_fill_gradient2(
          low = "#4388E8",
          mid = "#FFFFFF",
          high = "#E66B78",
          midpoint = 0,
          limits = c(-1, 1),
          name = "Spearman Rho"
        ) +
        ggplot2::labs(
          title = "Spearman Rank Correlation Matrix",
          subtitle = "Pairwise-complete correlations across preprocessed features",
          x = NULL,
          y = NULL
        ) +
        theme_dashboard() +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, vjust = 1),
          legend.position = "right"
        )
    }, res = 110)

    output$stat_numeric_table <- DT::renderDT({
      data <- numeric_comparisons |>
        dplyr::mutate(
          variable = unname(pretty_feature_labels[variable]),
          median_non_defaulted = format_number(median_non_defaulted, 2),
          median_defaulted = format_number(median_defaulted, 2),
          mean_non_defaulted = format_number(mean_non_defaulted, 2),
          mean_defaulted = format_number(mean_defaulted, 2),
          mean_difference = format_number(mean_difference, 2),
          wilcoxon_p_value = ifelse(wilcoxon_p_value < 1e-4, "< 0.0001", formatC(wilcoxon_p_value, format = "f", digits = 4))
        ) |>
        dplyr::select(
          Feature = variable,
          `Non-default median` = median_non_defaulted,
          `Default median` = median_defaulted,
          `Non-default mean` = mean_non_defaulted,
          `Default mean` = mean_defaulted,
          `Mean difference` = mean_difference,
          `Wilcoxon p-value` = wilcoxon_p_value
        )
      create_datatable(data, page_length = 8, search = TRUE)
    })

    output$stat_segment_table <- DT::renderDT({
      data <- segment_rates |>
        dplyr::mutate(
          segment = dplyr::case_when(
            segment == "age_band" ~ "Age band",
            segment == "monthly_income_band" ~ "Income band",
            segment == "dependents_band" ~ "Dependents",
            TRUE ~ segment
          ),
          borrower_count = scales::comma(borrower_count),
          default_rate = scales::percent(default_rate, accuracy = 0.1),
          ci = paste0(
            scales::percent(default_rate_ci_lower, accuracy = 0.1),
            " – ",
            scales::percent(default_rate_ci_upper, accuracy = 0.1)
          )
        ) |>
        dplyr::select(
          Segment = segment,
          Band = band,
          Borrowers = borrower_count,
          `Default rate` = default_rate,
          `Wilson 95% interval` = ci
        )
      create_datatable(data, page_length = 8, search = TRUE)
    })
  })
}
