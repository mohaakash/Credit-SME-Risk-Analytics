# Module: Credit Model Evaluation & Benchmarks
# Handles ROC comparison, probability calibration curves, lift by decile, and threshold trade-offs.

mod_models_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Model Evaluation",
      "Scorecard Discrimination & Calibration",
      "Comparison of the baseline logistic model, Weight of Evidence (WoE) scorecard, CART tree, calibrated Random Forest, and calibrated XGBoost on held-out test data."
    ),
    uiOutput(ns("model_recommendation")),
    bslib::card(
      bslib::card_header("Held-Out Test Set Performance Comparison"),
      bslib::card_body(DT::DTOutput(ns("model_metrics_table"))),
      full_screen = TRUE
    ),
    div(
      class = "row g-3",
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Receiver Operating Characteristic (ROC)"),
          bslib::card_body(plotOutput(ns("model_roc"), height = "380px")),
          full_screen = TRUE
        )
      ),
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Probability Calibration by Risk Decile"),
          bslib::card_body(plotOutput(ns("model_calibration_plot"), height = "380px")),
          full_screen = TRUE
        )
      )
    ),
    bslib::card(
      bslib::card_header("Lift by Risk Decile (Default Concentration)"),
      bslib::card_body(plotOutput(ns("model_lift_plot"), height = "360px")),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Demonstration Decision Threshold Trade-Offs"),
      bslib::card_body(DT::DTOutput(ns("model_threshold_table"))),
      full_screen = TRUE
    )
  )
}

mod_models_server <- function(id, model_metrics, model_calibration, model_lift, model_thresholds, model_roc_curves, model_display_labels) {
  moduleServer(id, function(input, output, session) {
    
    output$model_recommendation <- renderUI({
      woe_metrics <- model_metrics[model_metrics$model == "Logistic_WOE", , drop = FALSE]
      xgb_metrics <- model_metrics[model_metrics$model == "XGBoost", , drop = FALSE]
      rf_metrics <- model_metrics[model_metrics$model == "RandomForest", , drop = FALSE]
      if (nrow(woe_metrics) == 0 || nrow(xgb_metrics) == 0) {
        return(div(class = "alert alert-warning", "Model comparison artifacts are incomplete."))
      }

      div(
        class = "alert alert-success d-flex align-items-start mb-4",
        icon("award", class = "fs-3 text-success me-3 mt-1"),
        div(
          tags$strong("Benchmark Summary: "),
          paste0(
            "Calibrated XGBoost achieves the top ranking discrimination and probability accuracy on held-out test data (ROC-AUC ",
            sprintf("%.3f", xgb_metrics$roc_auc[[1]]),
            "; Brier score ",
            sprintf("%.4f", xgb_metrics$brier_score[[1]]),
            "). WoE Logistic is the strongest interpretable regulatory candidate (ROC-AUC ",
            sprintf("%.3f", woe_metrics$roc_auc[[1]]),
            "; Brier score ",
            sprintf("%.4f", woe_metrics$brier_score[[1]]),
            "). Both ensemble models are probability-calibrated."
          )
        )
      )
    })

    output$model_metrics_table <- DT::renderDT({
      data <- model_metrics |>
        dplyr::mutate(
          model = unname(model_display_labels[model]),
          default_rate = scales::percent(default_rate, accuracy = 0.1),
          borrower_count = scales::comma(borrower_count),
          roc_auc = sprintf("%.3f", roc_auc),
          pr_auc = sprintf("%.3f", pr_auc),
          ks = sprintf("%.3f", ks),
          brier_score = sprintf("%.4f", brier_score)
        ) |>
        dplyr::select(
          Model = model,
          `Test borrowers` = borrower_count,
          `Default rate` = default_rate,
          `ROC-AUC` = roc_auc,
          `PR-AUC` = pr_auc,
          KS = ks,
          `Brier score` = brier_score
        )
      create_datatable(data, page_length = 5, search = FALSE)
    })

    output$model_roc <- renderPlot({
      colors <- c(
        Logistic = "#4388E8",
        Logistic_WOE = "#8065D6",
        CART = "#E66B78",
        RandomForest = "#35A85A",
        XGBoost = "#E3AF3E"
      )
      auc_labels <- stats::setNames(
        paste0(unname(model_display_labels[model_metrics$model]), " (AUC = ", sprintf("%.3f", model_metrics$roc_auc), ")"),
        model_metrics$model
      )
      roc_data <- model_roc_curves
      roc_data$ModelLabel <- auc_labels[roc_data$model]
      
      ggplot2::ggplot(roc_data, ggplot2::aes(x = false_positive_rate, y = true_positive_rate, color = model)) +
        ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#9CA3AF") +
        ggplot2::geom_line(linewidth = 1.1) +
        ggplot2::scale_color_manual(
          values = colors,
          labels = auc_labels,
          name = "Model"
        ) +
        ggplot2::scale_x_continuous(labels = scales::percent, expand = c(0.01, 0.01)) +
        ggplot2::scale_y_continuous(labels = scales::percent, expand = c(0.01, 0.01)) +
        ggplot2::labs(
          title = "Held-Out ROC Curves",
          subtitle = "Discrimination ability across benchmark credit scoring architectures",
          x = "False Positive Rate (1 - Specificity)",
          y = "True Positive Rate (Sensitivity)"
        ) +
        theme_dashboard() +
        ggplot2::theme(legend.position = "right")
    }, res = 110)

    output$model_calibration_plot <- renderPlot({
      colors <- c(
        Logistic = "#4388E8",
        Logistic_WOE = "#8065D6",
        CART = "#E66B78",
        RandomForest = "#35A85A",
        XGBoost = "#E3AF3E"
      )
      
      ggplot2::ggplot(model_calibration, ggplot2::aes(x = predicted_default_rate, y = observed_default_rate, color = model)) +
        ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#9CA3AF") +
        ggplot2::geom_line(linewidth = 1) +
        ggplot2::geom_point(size = 2.5) +
        ggplot2::scale_color_manual(
          values = colors,
          labels = model_display_labels,
          name = "Model"
        ) +
        ggplot2::scale_x_continuous(labels = scales::percent, expand = c(0.02, 0.02)) +
        ggplot2::scale_y_continuous(labels = scales::percent, expand = c(0.02, 0.02)) +
        ggplot2::labs(
          title = "Calibration by Risk Decile",
          subtitle = "Mean predicted probability vs. observed default rate (Dashed = Perfect calibration)",
          x = "Mean Predicted Default Probability",
          y = "Observed Default Rate"
        ) +
        theme_dashboard() +
        ggplot2::theme(legend.position = "right")
    }, res = 110)

    output$model_lift_plot <- renderPlot({
      colors <- c(
        Logistic = "#4388E8",
        Logistic_WOE = "#8065D6",
        CART = "#E66B78",
        RandomForest = "#35A85A",
        XGBoost = "#E3AF3E"
      )
      
      ggplot2::ggplot(model_lift, ggplot2::aes(x = factor(decile), y = lift, color = model, group = model)) +
        ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "#9CA3AF") +
        ggplot2::geom_line(linewidth = 1) +
        ggplot2::geom_point(size = 2.5) +
        ggplot2::scale_color_manual(
          values = colors,
          labels = model_display_labels,
          name = "Model"
        ) +
        ggplot2::labs(
          title = "Lift by Risk Decile",
          subtitle = "Relative concentration of defaults compared to random selection (Decile 1 = Highest Risk)",
          x = "Risk Decile",
          y = "Cumulative Lift"
        ) +
        theme_dashboard() +
        ggplot2::theme(legend.position = "right")
    }, res = 110)

    output$model_threshold_table <- DT::renderDT({
      data <- model_thresholds |>
        dplyr::mutate(
          model = unname(model_display_labels[model]),
          threshold = scales::percent(threshold, accuracy = 1),
          sensitivity = scales::percent(sensitivity, accuracy = 0.1),
          specificity = scales::percent(specificity, accuracy = 0.1),
          precision = scales::percent(precision, accuracy = 0.1),
          false_negative_rate = scales::percent(false_negative_rate, accuracy = 0.1),
          flagged_rate = scales::percent(flagged_rate, accuracy = 0.1)
        ) |>
        dplyr::select(
          Model = model,
          Threshold = threshold,
          Sensitivity = sensitivity,
          Specificity = specificity,
          Precision = precision,
          `False-negative rate` = false_negative_rate,
          `Flagged rate` = flagged_rate
        )
      create_datatable(data, page_length = 10, search = TRUE)
    })
  })
}
