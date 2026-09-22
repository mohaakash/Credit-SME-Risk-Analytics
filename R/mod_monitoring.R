# Module: Model Governance & Monitoring Diagnostics
# Handles quarterly PSI progression, feature drift tracking, and out-of-time calibration.

mod_monitoring_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Production Monitoring",
      "Out-of-Time Stability & Vintage Tracking",
      "Track credit score stability and input feature drift across quarterly application cohorts (2022Q1–2023Q4). The reference baseline is Baseline 2022-H1."
    ),
    div(
      class = "alert alert-info d-flex align-items-center mb-4",
      icon("circle-info", class = "fs-4 me-3 text-primary"),
      div("Deterministic quarterly vintages enable realistic out-of-time Population Stability Index (PSI) tracking against Baseline 2022-H1 (2022Q1 + 2022Q2, n=37,104) without artificial train/test split confusion.")
    ),
    div(
      class = "row g-3",
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Quarterly Score PSI Progression vs Baseline 2022-H1"),
          bslib::card_body(plotOutput(ns("monitoring_psi_trend_plot"), height = "360px")),
          full_screen = TRUE
        )
      ),
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Feature Distribution Shift (PSI vs Latest Vintage)"),
          bslib::card_body(plotOutput(ns("monitoring_psi_plot"), height = "360px")),
          full_screen = TRUE
        )
      )
    ),
    bslib::card(
      bslib::card_header("Prediction Score Decile Distribution (Baseline 2022-H1 vs Latest Vintage 2023Q4)"),
      bslib::card_body(plotOutput(ns("monitoring_prediction_plot"), height = "340px")),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Model Governance & Monitoring Scope"),
      bslib::card_body(DT::DTOutput(ns("monitoring_summary_table"))),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Feature Drift & Missingness Change Summary"),
      bslib::card_body(DT::DTOutput(ns("monitoring_feature_table"))),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Latest Vintage Calibration Check by Decile (2023Q4)"),
      bslib::card_body(DT::DTOutput(ns("monitoring_calibration_table"))),
      full_screen = TRUE
    )
  )
}

mod_monitoring_server <- function(id, monitoring_summary, monitoring_psi, monitoring_psi_trends, monitoring_feature_drift, monitoring_calibration, monitoring_feature_labels) {
  moduleServer(id, function(input, output, session) {
    
    output$monitoring_psi_trend_plot <- renderPlot({
      trend_data <- monitoring_psi_trends |>
        dplyr::filter(metric_type == "prediction", variable == "predicted_risk")
      
      ggplot2::ggplot(trend_data, ggplot2::aes(x = quarter, y = psi)) +
        ggplot2::geom_col(fill = "#4388E8", width = 0.5) +
        ggplot2::geom_hline(yintercept = 0.10, linetype = "dashed", color = "#E3AF3E", linewidth = 1) +
        ggplot2::geom_text(
          ggplot2::aes(label = sprintf("%.4f", psi)),
          vjust = -0.4,
          size = 3.6,
          fontface = "bold",
          color = "#374151"
        ) +
        ggplot2::annotate(
          "text",
          x = 1.5,
          y = 0.105,
          label = "Stability Threshold (0.10)",
          color = "#D97706",
          size = 3.2,
          fontface = "italic"
        ) +
        ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.25))) +
        ggplot2::labs(
          title = "Score PSI Progression vs Baseline 2022-H1",
          subtitle = "Out-of-time population stability index across quarterly application cohorts",
          x = "Application Vintage",
          y = "Population Stability Index (PSI)"
        ) +
        theme_dashboard()
    }, res = 110)

    output$monitoring_psi_plot <- renderPlot({
      values <- monitoring_feature_drift |>
        dplyr::arrange(psi) |>
        dplyr::slice_tail(n = min(10, nrow(monitoring_feature_drift)))
      values$label <- unname(monitoring_feature_labels[values$variable])
      values$label <- factor(values$label, levels = values$label)
      
      ggplot2::ggplot(values, ggplot2::aes(x = psi, y = label)) +
        ggplot2::geom_col(fill = "#2B9EAB", width = 0.55) +
        ggplot2::geom_vline(xintercept = 0.10, linetype = "dashed", color = "#E3AF3E", linewidth = 1) +
        ggplot2::geom_text(
          ggplot2::aes(label = sprintf("%.4f", psi)),
          hjust = -0.15,
          size = 3.5,
          fontface = "bold",
          color = "#374151"
        ) +
        ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.25))) +
        ggplot2::labs(
          title = "Top Feature PSI (Baseline vs Latest 2023Q4)",
          subtitle = "Screening for input distribution drift (Dashed = 0.10 threshold)",
          x = "Feature PSI",
          y = NULL
        ) +
        theme_dashboard()
    }, res = 110)

    output$monitoring_prediction_plot <- renderPlot({
      values <- monitoring_psi |>
        dplyr::filter(metric_type == "prediction", variable == "predicted_risk")
      
      plot_df <- rbind(
        data.frame(bin = values$bin, Cohort = "Baseline (2022-H1)", pct = values$reference_pct),
        data.frame(bin = values$bin, Cohort = "Latest Vintage (2023Q4)", pct = values$comparison_pct)
      )
      plot_df$Cohort <- factor(plot_df$Cohort, levels = c("Baseline (2022-H1)", "Latest Vintage (2023Q4)"))
      
      ggplot2::ggplot(plot_df, ggplot2::aes(x = bin, y = pct, fill = Cohort)) +
        ggplot2::geom_col(position = "dodge", width = 0.6) +
        ggplot2::scale_fill_manual(values = c("Baseline (2022-H1)" = "#91C3CB", "Latest Vintage (2023Q4)" = "#4388E8")) +
        ggplot2::scale_y_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.15))) +
        ggplot2::labs(
          title = "Score Distribution: Baseline vs Latest Vintage",
          subtitle = "Share of non-missing predicted probabilities across reference-quantile bins",
          x = "Score Decile Bin",
          y = "Share of Applications"
        ) +
        theme_dashboard() +
        ggplot2::theme(legend.position = "top")
    }, res = 110)

    output$monitoring_summary_table <- DT::renderDT({
      data <- monitoring_summary |>
        dplyr::rename(
          Check = check,
          Status = status,
          Details = details
        )
      create_datatable(data, page_length = 10, search = FALSE)
    })

    output$monitoring_feature_table <- DT::renderDT({
      data <- monitoring_feature_drift |>
        dplyr::mutate(
          variable = unname(monitoring_feature_labels[variable]),
          reference_mean = sprintf("%.3f", reference_mean),
          comparison_mean = sprintf("%.3f", comparison_mean),
          reference_median = sprintf("%.3f", reference_median),
          comparison_median = sprintf("%.3f", comparison_median),
          psi = sprintf("%.4f", psi),
          missing_rate_difference = scales::percent(missing_rate_difference, accuracy = 0.01)
        ) |>
        dplyr::select(
          Feature = variable,
          `Baseline mean` = reference_mean,
          `Latest mean` = comparison_mean,
          `Baseline median` = reference_median,
          `Latest median` = comparison_median,
          `Missing change` = missing_rate_difference,
          PSI = psi,
          Interpretation = psi_interpretation
        )
      create_datatable(data, page_length = 10, search = TRUE)
    })

    output$monitoring_calibration_table <- DT::renderDT({
      data <- monitoring_calibration |>
        dplyr::filter(period == "2023Q4") |>
        dplyr::mutate(
          borrower_count = scales::comma(borrower_count),
          predicted_default_rate = scales::percent(predicted_default_rate, accuracy = 0.1),
          observed_default_rate = scales::percent(observed_default_rate, accuracy = 0.1),
          calibration_gap = scales::percent(calibration_gap, accuracy = 0.1),
          absolute_calibration_gap = scales::percent(absolute_calibration_gap, accuracy = 0.1)
        ) |>
        dplyr::select(
          Decile = decile,
          Borrowers = borrower_count,
          `Predicted default rate` = predicted_default_rate,
          `Observed default rate` = observed_default_rate,
          `Calibration gap` = calibration_gap,
          `Absolute gap` = absolute_calibration_gap
        )
      create_datatable(data, page_length = 10, search = FALSE)
    })
  })
}
