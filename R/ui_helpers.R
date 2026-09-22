# UI and Visualization Helpers for Consumer Credit Risk Dashboard

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(ggplot2)
  library(scales)
})

format_number <- function(value, digits = 0) {
  ifelse(
    is.na(value),
    "—",
    formatC(value, format = "f", digits = digits, big.mark = ",")
  )
}

format_percentage <- function(value, digits = 1) {
  ifelse(
    is.na(value),
    "—",
    paste0(formatC(value * 100, format = "f", digits = digits), "%")
  )
}

page_intro <- function(kicker, title, description) {
  tags$div(
    class = "page-intro mb-4 pb-3 border-bottom",
    tags$div(class = "text-uppercase fw-bold text-teal small tracking-wider", kicker),
    tags$h2(class = "display-6 fw-bold text-dark mt-1 mb-2", title),
    tags$p(class = "lead text-muted fs-6 mb-0", style = "max-width: 900px;", description)
  )
}

theme_dashboard <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      text = ggplot2::element_text(color = "#263442"),
      plot.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(1.1), margin = ggplot2::margin(b = 6), color = "#111827"),
      plot.subtitle = ggplot2::element_text(color = "#6B7280", size = ggplot2::rel(0.88), margin = ggplot2::margin(b = 10)),
      axis.title = ggplot2::element_text(face = "bold", size = ggplot2::rel(0.85), color = "#4B5563"),
      axis.text = ggplot2::element_text(color = "#4B5563", size = ggplot2::rel(0.82)),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "#F1F5F9"),
      legend.position = "top",
      legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = ggplot2::rel(0.85), color = "#374151"),
      plot.margin = ggplot2::margin(10, 14, 10, 10)
    )
}

create_datatable <- function(df, page_length = 10, search = TRUE) {
  DT::datatable(
    df,
    rownames = FALSE,
    class = "table table-hover table-striped table-sm align-middle",
    options = list(
      pageLength = page_length,
      dom = if (search) "<'d-flex justify-content-between align-items-center mb-2'lf>rt<'d-flex justify-content-between align-items-center mt-2'ip>" else "rt<'d-flex justify-content-between align-items-center mt-2'ip>",
      ordering = TRUE,
      scrollX = TRUE,
      autoWidth = TRUE,
      language = list(
        search = "_INPUT_",
        searchPlaceholder = "Search records...",
        lengthMenu = "Show _MENU_",
        paginate = list(previous = "‹", `next` = "›"),
        info = "Showing _START_ to _END_ of _TOTAL_ rows"
      )
    )
  )
}
