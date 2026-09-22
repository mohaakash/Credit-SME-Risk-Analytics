# Module: Dashboard Overview & KPI Metrics
# Handles live SQLite portfolio filtering, value boxes, and risk band breakdowns.

mod_overview_ui <- function(id) {
  ns <- NS(id)
  tagList(
    page_intro(
      "Executive Overview",
      "Portfolio Risk & Concentration",
      "Live SQL metrics across the retail credit portfolio. Risk bands are calibrated model outputs evaluated on 150,000 borrower applications."
    ),
    uiOutput(ns("overview_cards")),
    bslib::card(
      bslib::card_header(
        icon("filter", class = "me-2 text-teal"),
        "Portfolio Segment Filters (SQLite Query Engine)"
      ),
      bslib::card_body(
        div(
          class = "row g-3",
          div(class = "col-md-4", selectInput(ns("overview_age"), "Age Band", choices = c("All", "<30", "30-44", "45-59", "60+", "Missing"))),
          div(class = "col-md-4", selectInput(ns("overview_income"), "Monthly Income Status", choices = c("All", "Observed", "Missing"))),
          div(class = "col-md-4", selectInput(ns("overview_delinquency"), "90+ Day Delinquency History", choices = c("All", "No 90+ day events", "One or more 90+ day events", "Missing")))
        )
      )
    ),
    div(
      class = "row g-3",
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Risk-Band Distribution", class = "d-flex justify-content-between align-items-center"),
          bslib::card_body(plotOutput(ns("overview_risk_bands"), height = "340px")),
          full_screen = TRUE
        )
      ),
      div(
        class = "col-lg-6",
        bslib::card(
          bslib::card_header("Observed Default Rate by Age", class = "d-flex justify-content-between align-items-center"),
          bslib::card_body(plotOutput(ns("overview_age_default"), height = "340px")),
          full_screen = TRUE
        )
      )
    ),
    bslib::card(
      bslib::card_header("Filtered Risk-Band Performance Summary (SQLite Aggregation)"),
      bslib::card_body(DT::DTOutput(ns("overview_summary_table"))),
      full_screen = TRUE
    )
  )
}

mod_overview_server <- function(id, db_connection) {
  moduleServer(id, function(input, output, session) {
    
    overview_kpis <- reactive({
      db_get_portfolio_kpis(
        db_connection,
        age_band = input$overview_age,
        income_status = input$overview_income,
        delinquency_status = input$overview_delinquency
      )
    })

    output$overview_cards <- renderUI({
      kpis <- overview_kpis()
      bslib::layout_column_wrap(
        width = 1/4,
        bslib::value_box(
          title = "Total Borrowers",
          value = scales::comma(kpis$borrower_count),
          showcase = icon("users"),
          theme = "teal",
          p("Filtered SQLite records", class = "mb-0 text-muted small")
        ),
        bslib::value_box(
          title = "Observed Default Rate",
          value = scales::percent(kpis$default_rate, accuracy = 0.01),
          showcase = icon("percent"),
          theme = "primary",
          p("Serious delinquency in 2 yrs", class = "mb-0 text-muted small")
        ),
        bslib::value_box(
          title = "Mean Predicted Risk",
          value = scales::percent(kpis$mean_predicted_risk, accuracy = 0.01),
          showcase = icon("chart-line"),
          theme = "info",
          p("Calibrated scorecard score", class = "mb-0 text-muted small")
        ),
        bslib::value_box(
          title = "High / Very High Risk",
          value = scales::percent(kpis$high_risk_rate, accuracy = 0.1),
          showcase = icon("triangle-exclamation"),
          theme = "danger",
          p("Scorecard top 2 risk tiers", class = "mb-0 text-muted small")
        )
      )
    })

    output$overview_risk_bands <- renderPlot({
      counts_df <- db_get_risk_band_counts(
        db_connection,
        age_band = input$overview_age,
        income_status = input$overview_income,
        delinquency_status = input$overview_delinquency
      )
      all_bands <- c("Low", "Moderate", "High", "Very high")
      band_df <- data.frame(
        risk_band = factor(all_bands, levels = all_bands),
        borrower_count = 0L
      )
      if (nrow(counts_df) > 0) {
        m <- match(band_df$risk_band, counts_df$risk_band)
        band_df$borrower_count[!is.na(m)] <- counts_df$borrower_count[m[!is.na(m)]]
      }
      total_n <- sum(band_df$borrower_count)
      
      ggplot2::ggplot(band_df, ggplot2::aes(x = risk_band, y = borrower_count, fill = risk_band)) +
        ggplot2::geom_col(width = 0.55, show.legend = FALSE) +
        ggplot2::geom_text(
          ggplot2::aes(label = scales::comma(borrower_count)),
          vjust = -0.4,
          size = 3.8,
          fontface = "bold",
          color = "#374151"
        ) +
        ggplot2::scale_fill_manual(values = c(
          "Low" = "#2B9EAB",
          "Moderate" = "#4388E8",
          "High" = "#E3AF3E",
          "Very high" = "#E66B78"
        )) +
        ggplot2::scale_y_continuous(labels = scales::comma, expand = ggplot2::expansion(mult = c(0, 0.15))) +
        ggplot2::labs(
          title = paste0("Borrowers by Risk Band (N = ", scales::comma(total_n), ")"),
          subtitle = "Percentile-based risk scoring tiers",
          x = NULL,
          y = "Borrower Count"
        ) +
        theme_dashboard()
    }, res = 110)

    output$overview_age_default <- renderPlot({
      summary <- db_get_age_default_summary(
        db_connection,
        income_status = input$overview_income,
        delinquency_status = input$overview_delinquency
      )
      if (nrow(summary) == 0) return(NULL)
      order_levels <- c("<30", "30-44", "45-59", "60+", "Missing")
      summary$age_band <- factor(summary$age_band, levels = order_levels)
      summary <- summary[!is.na(summary$age_band), ]
      summary <- summary[order(summary$age_band), ]
      
      ggplot2::ggplot(summary, ggplot2::aes(x = age_band, y = default_rate)) +
        ggplot2::geom_col(fill = "#197682", width = 0.55) +
        ggplot2::geom_text(
          ggplot2::aes(label = paste0(scales::percent(default_rate, accuracy = 0.1), "\n(n=", scales::comma(borrower_count), ")")),
          vjust = -0.2,
          size = 3.4,
          lineheight = 0.9,
          color = "#1F2937"
        ) +
        ggplot2::scale_y_continuous(labels = scales::percent, expand = ggplot2::expansion(mult = c(0, 0.22))) +
        ggplot2::labs(
          title = "Observed Default Rate by Age Band",
          subtitle = "Serious delinquency within 2 years with sample sizes",
          x = "Age Band",
          y = "Default Rate"
        ) +
        theme_dashboard()
    }, res = 110)

    output$overview_summary_table <- DT::renderDT({
      table_data <- db_get_filtered_summary_table(
        db_connection,
        age_band = input$overview_age,
        income_status = input$overview_income,
        delinquency_status = input$overview_delinquency
      )
      if (nrow(table_data) == 0) {
        return(DT::datatable(data.frame(Message = "No borrowers match the selected filters.")))
      }
      table_data <- table_data |>
        dplyr::mutate(
          Borrowers = scales::comma(Borrowers),
          `Observed defaults` = scales::comma(`Observed defaults`),
          `Observed default rate` = scales::percent(`Default rate`, accuracy = 0.01),
          `Mean predicted risk` = scales::percent(`Mean predicted risk`, accuracy = 0.01)
        ) |>
        dplyr::select(`Risk band`, Borrowers, `Observed defaults`, `Observed default rate`, `Mean predicted risk`)
      create_datatable(table_data, page_length = 5, search = FALSE)
    })
  })
}
