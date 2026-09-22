# Module: Portfolio Performance & Segment Diagnostics
# Handles segment groupings and quarterly application vintages via SQLite.

mod_portfolio_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Segment Performance",
      "Delinquency Concentration & Cohorts",
      "Track default rates across borrower attributes and quarterly application vintages (2022Q1–2023Q4) queried live from indexed SQLite tables."
    ),
    bslib::card(
      bslib::card_header(icon("layer-group", class = "me-2 text-teal"), "Segment Dimension"),
      bslib::card_body(
        div(
          style = "max-width: 400px;",
          selectInput(
            ns("portfolio_group"),
            "Select Grouping Dimension",
            choices = c(
              "Age Band" = "age_band",
              "Income Availability" = "income_status",
              "90+ Day History" = "delinquency_90_status",
              "Demonstration Risk Band" = "risk_band",
              "Application Vintage (Quarterly)" = "vintage_quarter"
            )
          )
        )
      )
    ),
    bslib::card(
      bslib::card_header(textOutput(ns("portfolio_panel_title"), inline = TRUE)),
      bslib::card_body(plotOutput(ns("portfolio_segment_plot"), height = "380px")),
      full_screen = TRUE
    ),
    bslib::card(
      bslib::card_header("Segment Breakdown Table (Live SQL Query)"),
      bslib::card_body(DT::DTOutput(ns("portfolio_segment_table"))),
      full_screen = TRUE
    )
  )
}

mod_portfolio_server <- function(id, db_connection) {
  moduleServer(id, function(input, output, session) {
    
    output$portfolio_panel_title <- renderText({
      choices <- c(
        age_band = "Default Rate by Age Band",
        income_status = "Default Rate by Income Availability",
        delinquency_90_status = "Default Rate by 90+ Day History",
        risk_band = "Default Rate by Risk Band",
        vintage_quarter = "Default Rate by Application Vintage"
      )
      choices[[input$portfolio_group]]
    })

    portfolio_summary <- reactive({
      db_get_segment_summary(db_connection, input$portfolio_group) |>
        dplyr::arrange(dplyr::desc(default_rate))
    })

    output$portfolio_segment_plot <- renderPlot({
      summary <- portfolio_summary()
      if (nrow(summary) == 0) return(NULL)
      summary$band <- factor(summary$band, levels = rev(summary$band))
      
      ggplot2::ggplot(summary, ggplot2::aes(x = default_rate, y = band)) +
        ggplot2::geom_col(fill = "#2B9EAB", width = 0.55) +
        ggplot2::geom_text(
          ggplot2::aes(label = paste0(scales::percent(default_rate, accuracy = 0.1), " (n=", scales::comma(borrower_count), ")")),
          hjust = -0.1,
          size = 3.5,
          fontface = "bold",
          color = "#374151"
        ) +
        ggplot2::scale_x_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.25))) +
        ggplot2::labs(
          title = "Segment Observed Default Rate",
          subtitle = "Ranked by delinquency risk with cohort volumes",
          x = "Observed Default Rate",
          y = NULL
        ) +
        theme_dashboard()
    }, res = 110)

    output$portfolio_segment_table <- DT::renderDT({
      data <- portfolio_summary() |>
        dplyr::mutate(
          Borrowers = scales::comma(borrower_count),
          Defaults = scales::comma(default_count),
          default_rate = scales::percent(default_rate, accuracy = 0.01),
          mean_predicted_risk = scales::percent(mean_predicted_risk, accuracy = 0.01)
        ) |>
        dplyr::select(
          Segment = band,
          Borrowers,
          Defaults,
          `Observed default rate` = default_rate,
          `Mean predicted risk` = mean_predicted_risk
        )
      create_datatable(data, page_length = 8, search = TRUE)
    })
  })
}
