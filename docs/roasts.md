# Project Review & Roast: Credit-SME Risk Analytics and Monitoring Dashboard

## Executive Scorecard

| Dimension | Grade | Verdict |
| :--- | :---: | :--- |
| **Statistical & Scorecard Hygiene** | **A-** | WoE/IV built cleanly from scratch, stratified split, no data leakage, Wilson CIs. Excellent foundation. |
| **Documentation & Reproducibility** | **A+** | `renv`, fixed seeds, detailed markdown reports, transparent self-auditing. Elite tier. |
| **Domain Alignment** | **C** | Claims SME, but scores retail credit card holders with family dependents. |
| **Probability & Calibration Handling** | **D** | Blew up tree probabilities with uncalibrated weights and blamed the models. |
| **Monitoring Design** | **D+** | Technically correct PSI formula, but ran it on an I.I.D. train-vs-test split. |
| **Shiny & Frontend Architecture** | **C+** | 1,350-line monolith, Base R graphics, raw HTML tables, and brute-force CSS. |

---

## The Roast: Seven Deadly Sins

### 1. The "SME" Identity Crisis: Did Your Corporation Have a Baby?
The project repository is titled [`Credit-SME-Risk-Analytics-and-Monitoring-Dashboard`](file:///home/akash/projects/SME%20Risk%20Analytics/README.md#L1), and the folder is literally `SME Risk Analytics`.

Yet, the underlying dataset is the classic **2011 Kaggle "Give Me Some Credit" retail consumer dataset** ([`docs/data-dictionary.md`](file:///home/akash/projects/SME%20Risk%20Analytics/docs/data-dictionary.md#L1-L17)).
Where are the corporate financial metrics? EBITDA? Debt Service Coverage Ratio (DSCR)? Current ratio? Corporate balance sheets? Industry NAICS/SIC codes? Accounts receivable aging?
Instead, the risk features are:
- `age`: "How old is this Small and Medium Enterprise? 45 years old?"
- `number_of_dependents`: *"Excuse me, Mr. LLC, how many children are dependent on your family?"*
- `revolving_utilization_of_unsecured_lines`: Scoring personal credit cards and calling it corporate credit underwriting.

If an enterprise credit risk committee asked to inspect this SME risk engine, they would ask why your corporate risk assessment hinges on family dependents excluding the borrower.

---

### 2. The "Train vs. Test" Production Monitoring Comedy
In [`R/model_monitoring.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/model_monitoring.R#L1-L7) and [`reports/model-monitoring-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/model-monitoring-report.md#L30-L46), there is a full PSI (Population Stability Index), feature drift, and calibration monitoring suite... **comparing the 80% train split to the 20% test split from a single random stratified split.**

```text
Variable: predicted_risk | PSI: 0.0006 | "Stable demonstration"
Age PSI: 0.0003 | Open Lines PSI: 0.0005
```

Of course it is stable. The pipeline took 150,000 rows, randomly shuffled them with `set.seed(20260921)`, drew 30,000 rows, and then celebrated that two random draws from the exact same distribution did not experience macroeconomic drift. It is literally measuring random sampling noise to 4 decimal places and calling it drift monitoring.

---

### 3. The "SQL-Backed" Illusion
The README and architecture docs state: *"SQLite-backed KPI and portfolio queries."* There is even a standalone file [`sql/kpi_queries.sql`](file:///home/akash/projects/SME%20Risk%20Analytics/sql/kpi_queries.sql).

Then check [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L47-L48):
```r
db_connection <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
cleaned_data <- DBI::dbReadTable(db_connection, "training_clean")
```
That is the only SQL query executed in the entire 1,346-line Shiny application.
The app loads the entire 150,000-row table into RAM, leaves the database connection unclosed in the global environment, and proceeds to perform 100% of filtering, grouping, and aggregation in-memory with `dplyr`. SQLite was used as an over-engineered, slow `.csv` file.

---

### 4. The Tree Model Sabotage & Calibration Blindness
In [`R/train_models.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/train_models.R#L336-L375), class imbalance was handled via:
- Random Forest: `sampsize = rep(8020, 2)` (50/50 balanced downsampling).
- XGBoost: `scale_pos_weight = 13.96` (the negative-to-positive class ratio).

When `scale_pos_weight = 14` is applied without post-calibration, raw predicted probabilities are shifted into outer space. While the population default rate is 6.7%, raw XGBoost scores center around 50%.

In [`reports/modeling-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/modeling-report.md#L61-L100), XGBoost and Random Forest were then evaluated at fixed probability cutoffs of `3%`, `5%`, `10%`, and `20%`:
- At a 3% threshold, **XGBoost flagged 99.75% of all applicants** (Specificity: 0.27%).
- At a 10% threshold, it flagged 78.96% of borrowers.
- XGBoost Brier score was `0.1423` vs Logistic `0.0513`.

The report then concludes: *"None of the tree ensembles should be used for policy decisions without calibration... WoE Logistic is our preferred model."*
The ensemble models were penalized for uncalibrated prior shifts that could have been corrected with a one-line log-odds offset or Platt scaling.

---

### 5. The Free-Money Paradox: Take More Debt, Lower Your Risk!
In [`reports/statistical-analysis-report.md#L94`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/statistical-analysis-report.md#L94):
```text
term: log_debt_ratio | estimate: -0.1772 | odds_ratio: 0.8376 | p_value: < 1e-6
```
According to this preliminary model, **for every unit increase in log debt ratio, default odds decrease by 16%.**
Why? In the Kaggle dataset, whenever `MonthlyIncome` is missing, `DebtRatio` represents raw monthly debt expenditure in dollars (e.g. $4,000). When `MonthlyIncome` is present, it is a percentage (e.g. 0.35). While `debt_ratio > 10` was flagged, `log1p` was computed across these mixed definitions without segregation, producing a negative coefficient.

---

### 6. Base R Graphics & CSS Wrestling in Shiny 2026
In [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L817-L859), charts are rendered using Base R:
```r
graphics::barplot(...)
graphics::text(locations, ..., pos = 3, cex = 0.75)
```
Label coordinates are manually calculated with `ylim = c(0, max(...) * 1.28)` on static rendered images. Tables are rendered with `renderTable()`—raw HTML table tags with no search, pagination, or sorting.

Furthermore, [`app.R#L277-L300`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L277-L300) contains **200+ lines of custom CSS forcing `navbarPage` into a vertical sidebar**, fighting the Bootstrap layout instead of using `bslib::page_sidebar()`.

---

### 7. The Simulator's Inverted Driver Logic Bug
In [`app.R#L1324-L1327`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L1324-L1327):
```r
contributions <- sort(contributions[is.finite(contributions)], decreasing = TRUE)
positive <- head(contributions[contributions > 0], 4)
negative <- head(contributions[contributions < 0], 2)
```
When `contributions` is sorted in **decreasing** order, the subset `contributions < 0` is ordered from least negative to most negative (e.g. `c(-0.001, -0.015, -0.850)`). Calling `head(..., 2)` retrieves the **two weakest negative drivers**, hiding the borrower's strongest protective factors.

---

## The Good: Credit Where Credit is Due

1. **Methodological Transparency**: Every markdown report ([`data-quality-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/data-quality-report.md), [`modeling-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/modeling-report.md), [`model-monitoring-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/model-monitoring-report.md)) clearly identifies limitations, assumptions, seeds, and warnings against automated production lending.
2. **From-Scratch WoE/IV**: [`R/feature_engineering.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/feature_engineering.R#L143-L203) implements quantile binning, Laplace smoothing, Weight of Evidence, and Information Value cleanly without brittle third-party dependencies.
3. **Reproducibility**: Environment tracking via [`renv.lock`](file:///home/akash/projects/SME%20Risk%20Analytics/renv.lock), explicit script run sequences, and fixed seeds make the pipeline fully reproducible.
4. **Leakage Protection**: Feature engineering medians and WoE bins are fitted strictly on the training partition and transformed onto the held-out test partition.

---

## Actionable Improvement Roadmap

### 1. Domain Alignment or Realistic SME Augmentation
- **Option A (Honest Positioning)**: Rebrand the project to **Consumer Credit Scorecard & Risk Monitoring Dashboard**. It is already an exemplary consumer scorecard pipeline.
- **Option B (Synthetic SME Funnel & Vintages)**: Generate realistic business fields:
  - Corporate structure: Annual Revenue, DSCR, Years in Business, Industry Sector (NAICS).
  - Funnel milestones: *Application Received → Automated Filter → Underwriter Review → Approved → Disbursed*.
  - Cohorts: Quarterly vintages (2022Q1 to 2024Q4) to give PSI and feature drift actual temporal meaning.

### 2. Probability Calibration for Ensembles
To restore calibrated probabilities when using `scale_pos_weight = w`:
$$\text{logit}(p_{calibrated}) = \text{logit}(p_{raw}) - \log(w)$$

```r
adjust_xgboost_probs <- function(p_raw, pos_weight) {
  raw_odds <- p_raw / (1 - p_raw)
  calibrated_odds <- raw_odds / pos_weight
  calibrated_odds / (1 + calibrated_odds)
}
```
Or fit an isotonic/Platt scaling calibrator on a validation slice:
```r
calibrator <- stats::glm(target ~ score, data = val_data, family = stats::binomial())
calibrated_score <- stats::predict(calibrator, newdata = test_data, type = "response")
```

### 3. Fix the Simulator Driver Sorting
In [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L1324-L1327):
```r
# Top risk enhancers (largest positive contributions)
positive <- head(sort(contributions[contributions > 0], decreasing = TRUE), 4)

# Top protective factors (largest negative contributions)
negative <- head(sort(contributions[contributions < 0], decreasing = FALSE), 2)
```

### 4. Modernize Shiny UI & Visualizations
- Switch from `navbarPage` + custom CSS to `bslib::page_sidebar()`.
- Replace `renderTable()` with `DT::renderDT()`.
- Upgrade Base R plots to `plotly::plot_ly()` or `ggplot2` + `plotly::ggplotly()` for responsive hovers and zoom.

### 5. Modularize `app.R`
Decompose the 1,346-line monolith into Shiny modules under `R/`:
```text
R/
├── mod_overview.R
├── mod_portfolio.R
├── mod_statistics.R
├── mod_models.R
├── mod_monitoring.R
└── mod_simulator.R
```

### 6. Introduce Automated Unit Testing
Add `testthat` to verify core functions:
```bash
tests/
└── testthat/
    ├── test-feature_engineering.R  # Verify WoE formulas & Laplace smoothing
    ├── test-data_cleaning.R        # Verify sentinel 96/98 conversion
    └── test-model_metrics.R        # Verify KS, ROC-AUC, Brier score calculations
```
