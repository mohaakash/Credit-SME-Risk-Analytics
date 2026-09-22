# Module: Applicant Risk Simulator & Attribution
# Handles interactive applicant feature entry, real-time risk scoring, and directional risk drivers.

mod_simulator_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Interactive Scoring",
      "Applicant Risk Simulator & Attribution",
      "Simulate individual credit applicants through the calibrated scorecard pipeline and inspect top positive and negative risk driver attributions."
    ),
    div(
      class = "row g-4",
      div(
        class = "col-lg-5",
        bslib::card(
          bslib::card_header(icon("sliders", class = "me-2 text-teal"), "Borrower Attributes"),
          bslib::card_body(
            numericInput(ns("sim_age"), "Age", value = 45, min = 18, max = 100, step = 1),
            numericInput(ns("sim_utilization"), "Revolving Line Utilization (0 to 1+)", value = 0.35, min = 0, step = 0.01),
            numericInput(ns("sim_debt_ratio"), "Debt-to-Income Ratio (DTI)", value = 0.40, min = 0, step = 0.01),
            checkboxInput(ns("sim_income_missing"), "Monthly Income Unavailable", value = FALSE),
            numericInput(ns("sim_income"), "Monthly Income ($)", value = 5000, min = 0, step = 100),
            numericInput(ns("sim_open_lines"), "Open Credit Lines and Loans", value = 8, min = 0, step = 1),
            numericInput(ns("sim_30_59"), "30-59 Days Past Due Events", value = 0, min = 0, step = 1),
            numericInput(ns("sim_60_89"), "60-89 Days Past Due Events", value = 0, min = 0, step = 1),
            numericInput(ns("sim_90"), "90+ Days Late Events", value = 0, min = 0, step = 1),
            numericInput(ns("sim_real_estate"), "Real Estate Loans or Lines", value = 1, min = 0, step = 1),
            checkboxInput(ns("sim_dependents_missing"), "Dependents Unavailable", value = FALSE),
            numericInput(ns("sim_dependents"), "Number of Dependents", value = 1, min = 0, step = 1)
          )
        )
      ),
      div(
        class = "col-lg-7",
        bslib::card(
          bslib::card_header(icon("gauge", class = "me-2 text-teal"), "Underwriting Risk Assessment"),
          bslib::card_body(uiOutput(ns("simulator_result")))
        ),
        bslib::card(
          bslib::card_header(icon("chart-simple", class = "me-2 text-teal"), "Top Feature Risk Drivers & Protective Factors"),
          bslib::card_body(
            p(class = "text-muted small mb-3", "Relative log-odds contribution compared to median borrower: positive values increase default risk; negative values protect against default."),
            DT::DTOutput(ns("simulator_drivers"))
          )
        )
      )
    )
  )
}

mod_simulator_server <- function(id, logistic_model, model_preprocessor, assign_risk_band, pretty_feature_labels) {
  moduleServer(id, function(input, output, session) {
    
    simulator_features <- reactive({
      data.frame(
        age = input$sim_age,
        revolving_utilization_of_unsecured_lines = input$sim_utilization,
        debt_ratio = input$sim_debt_ratio,
        monthly_income = if (isTRUE(input$sim_income_missing)) NA_real_ else input$sim_income,
        number_of_open_credit_lines_and_loans = input$sim_open_lines,
        number_of_time30_59days_past_due_not_worse = input$sim_30_59,
        number_of_time60_89days_past_due_not_worse = input$sim_60_89,
        number_of_times90days_late = input$sim_90,
        number_real_estate_loans_or_lines = input$sim_real_estate,
        number_of_dependents = if (isTRUE(input$sim_dependents_missing)) NA_real_ else input$sim_dependents,
        revolving_utilization_gt_1 = as.integer(input$sim_utilization > 1),
        debt_ratio_gt_10 = as.integer(input$sim_debt_ratio > 10)
      )
    })

    simulator_prediction <- reactive({
      features <- build_model_features(simulator_features())
      processed <- apply_model_preprocessor(features, model_preprocessor)
      score <- as.numeric(stats::predict(logistic_model, newdata = processed, type = "response"))
      list(score = score, band = assign_risk_band(score), features = processed)
    })

    output$simulator_result <- renderUI({
      result <- simulator_prediction()
      div(
        class = "risk-result",
        div(
          class = "risk-box risk-score-box",
          div(class = "fw-semibold small text-uppercase tracking-wider", "Predicted Default Probability"),
          div(class = "risk-val", scales::percent(result$score, accuracy = 0.01)),
          div(class = "small text-muted", "Calibrated scorecard model score")
        ),
        div(
          class = "risk-box risk-band-box",
          div(class = "fw-semibold small text-uppercase tracking-wider", "Demonstration Risk Tier"),
          div(class = "risk-val", as.character(result$band)),
          div(class = "small text-muted", "Percentile-based underwriting tier")
        )
      )
    })

    output$simulator_drivers <- DT::renderDT({
      result <- simulator_prediction()
      coefficients <- stats::coef(logistic_model)[model_preprocessor$feature_names]
      medians <- model_preprocessor$medians[model_preprocessor$feature_names]
      feature_values <- as.numeric(result$features[1, model_preprocessor$feature_names])
      names(feature_values) <- model_preprocessor$feature_names
      contributions <- (feature_values - medians) * coefficients
      contributions_pos <- contributions[is.finite(contributions) & contributions > 0]
      contributions_neg <- contributions[is.finite(contributions) & contributions < 0]
      positive <- head(sort(contributions_pos, decreasing = TRUE), 4)
      negative <- head(sort(contributions_neg, decreasing = FALSE), 2)
      driver_rows <- rbind(
        if (length(positive) > 0) data.frame(Direction = "Higher estimated risk", Feature = names(positive), contribution = unname(positive)) else NULL,
        if (length(negative) > 0) data.frame(Direction = "Lower estimated risk", Feature = names(negative), contribution = unname(negative)) else NULL
      )
      if (is.null(driver_rows) || nrow(driver_rows) == 0) {
        return(DT::datatable(data.frame(Message = "No directional contributions available.")))
      }
      data <- data.frame(
        Direction = driver_rows$Direction,
        Feature = unname(pretty_feature_labels[driver_rows$Feature]),
        `Relative contribution` = sprintf("%+.4f", driver_rows$contribution),
        check.names = FALSE,
        row.names = NULL
      )
      create_datatable(data, page_length = 6, search = FALSE)
    })
  })
}
