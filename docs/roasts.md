# Project Review & Roast: Consumer Credit Risk Analytics and Monitoring Dashboard

## Executive Scorecard

| Dimension | Grade | Verdict |
| :--- | :---: | :--- |
| **Statistical & Scorecard Hygiene** | **A-** | WoE/IV built cleanly from scratch, stratified split, no data leakage, Wilson CIs. Excellent foundation. |
| **Documentation & Reproducibility** | **A+** | `renv`, fixed seeds, detailed markdown reports, transparent self-auditing. Elite tier. |
| **Domain Alignment** | **A-** | Rebranded to Consumer Credit Risk; features and framing now fully align with retail cardholder data. |
| **Probability & Calibration Handling** | **A** | XGBoost calibrated via Bayesian odds adjustment and RF via OOB Platt scaling; Brier score plummeted to 0.0493. |
| **Monitoring Design** | **A-** | Quarterly vintages (2022Q1–2023Q4), Baseline 2022-H1 reference, out-of-time PSI trends, and drift tracking. |
| **Database & SQL Architecture** | **A-** | Parameterized SQLite queries (`R/db_queries.R`), indexed tables, zero boot table scans, clean connection lifecycle. |
| **Shiny & Frontend Architecture** | **A+** | 154-line orchestrator decomposed into 6 Shiny modules under `R/`, `bslib` Bootstrap 5 layout, interactive `DT` tables, and `ggplot2` graphics. |
| **Automated Testing Suite** | **A+** | 44 automated unit tests via `testthat` covering data cleaning, WoE calculations, parameterized SQL, and Bayesian calibration with 100% pass rate. |

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

---

## Sprint 1: Completed Resolutions

- [x] **Issue 1 (Domain Alignment)**: Project rebranded cleanly to **Consumer Credit Risk Analytics and Monitoring Dashboard**, aligning documentation, headers, and UI with the true nature of the Kaggle retail consumer dataset.
- [x] **Issue 5 (Free-Money Paradox)**: Decoupled raw dollar debt from debt-to-income ratio in [`R/feature_engineering.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/feature_engineering.R) and [`R/statistical_analysis.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/statistical_analysis.R). Missing income DTI is cleanly set to `NA` and imputed with median, while observed DTI is capped at 10.0. The preliminary logistic regression `log_debt_ratio` coefficient flipped from **-0.177** to **+0.220** (odds ratio: **1.25**, $p = 0.0003$), restoring economic credit risk validity.
- [x] **Issue 7 (Simulator Driver Bug)**: Fixed contribution sorting logic in [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R#L1324-L1327) by segregating positive and negative contributions and sorting negatives in ascending order (`decreasing = FALSE`), correctly surfacing the applicant's top protective risk factors.

---

## Sprint 2: Completed Resolutions

- [x] **Issue 4 (Tree Model Sabotage & Calibration Blindness)**:
  - **XGBoost Bayesian Odds Calibration**: Applied exact Bayesian prior odds adjustment:
    $$p_{calibrated} = \frac{p_{raw}}{p_{raw} + w \cdot (1 - p_{raw})}$$
    where $w = \text{scale\_pos\_weight} = 13.96$. XGBoost held-out test Brier score plummeted from **0.1425** to **0.0493** (the lowest probability error across all models, outperforming the logistic baseline at 0.0526 and WoE logistic at 0.0513).
  - **Random Forest Out-of-Bag Platt Scaling**: Calibrated balanced Random Forest predictions using a logistic calibrator fitted on its out-of-bag training votes ($rf\$votes[, '1']$), avoiding test data leakage. Brier score plummeted from **0.1449** to **0.0513**.
  - **Threshold Realism**: At a 10% policy cutoff, XGBoost flagged rate normalized from **78.96%** to **16.81%** (Sensitivity: 67.70%, Specificity: 86.84%, Precision: 26.93%), and Random Forest flagged rate normalized from **49.34%** to **18.83%** (Sensitivity: 70.34%, Specificity: 84.87%, Precision: 24.98%).
  - Updated [`reports/modeling-report.md`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/modeling-report.md) with the calibrated metrics, calibration curves, and updated benchmark interpretation.

---

## Sprint 3: Completed Resolutions

- [x] **Issue 2 (Train vs. Test Production Monitoring Comedy)**:
  - **Deterministic Application Vintages**: Assigned deterministic quarterly application dates spanning `2022Q1` through `2023Q4` (150,000 records, ~18,500–18,990 applications per quarter) in [`R/data_cleaning.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/data_cleaning.R).
  - **Out-of-Time Reference & Cohort Tracking**: In [`R/model_monitoring.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/model_monitoring.R), established `Baseline_2022_H1` (2022Q1 + 2022Q2, $n = 37,104$) as the monitoring benchmark, tracking subsequent out-of-time quarters (`2022Q3` through `2023Q4`).
  - **Multi-Period PSI Trends**: Generated [`reports/generated/monitoring_psi_trends.csv`](file:///home/akash/projects/SME%20Risk%20Analytics/reports/generated/monitoring_psi_trends.csv), tracking quarterly PSI progression for predicted risk and all 10 scorecard features against industry thresholds ($< 0.10$ Stable, $0.10-0.25$ Moderate Shift, $\ge 0.25$ Substantial Shift).
  - **Shiny Monitoring Dashboard Upgrade**: Embedded a multi-period quarterly PSI progression bar chart and updated distribution comparisons in [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R).
- [x] **Issue 3 (The SQL-Backed Illusion)**:
  - **Standalone Parameterized SQL Query Helpers**: Implemented [`R/db_queries.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/db_queries.R) providing parameterized queries:
    - `db_get_portfolio_kpis()`: Aggregate borrower count, observed default rate, mean predicted risk, and high-risk share.
    - `db_get_risk_band_counts()`: Risk band breakdown across Low, Moderate, High, and Very High.
    - `db_get_age_default_summary()`: Age-band default rate and borrower volume.
    - `db_get_segment_summary()`: Group-level performance across age, income availability, delinquency history, risk bands, and application vintages.
    - `db_get_vintage_performance()`: Cohort tracking across quarterly application vintages.
    - `db_get_filtered_summary_table()`: Filtered risk band summary table.
  - **SQL Repository Sync**: Updated [`sql/kpi_queries.sql`](file:///home/akash/projects/SME%20Risk%20Analytics/sql/kpi_queries.sql) with matching parameterized queries.
  - **Indexed SQLite Tables**: Pre-scored and indexed `predicted_risk`, `risk_band`, `vintage_quarter`, `age_band`, `income_status`, and `delinquency_90_status` directly in SQLite table `training_clean` in [`R/train_models.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/train_models.R).
  - **Zero Boot Latency & Connection Cleanup**: Completely eliminated `DBI::dbReadTable(db_connection, "training_clean")` and 150k in-memory rescoring from [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R). All dashboard KPI cards, plots, and tables execute live parameterized SQL against indexed SQLite columns. Registered `shiny::onStop()` to ensure clean connection termination on app shutdown.

---

## Sprint 4: Completed Resolutions

- [x] **Issue 6 (Base R Graphics & CSS Wrestling in Shiny 2026)**:
  - **Modern Layout via `bslib::page_navbar`**:
    - Replaced the 200+ lines of custom CSS overriding `.navbar` with modern `bslib::page_navbar()` powered by Bootstrap 5 (`preset = "bootstrap"`), responsive grid layouts, and mobile-friendly navigation.
    - Upgraded top-level KPI metrics to native `bslib::value_box()` components with icon showcases and contextual themes (`teal`, `primary`, `info`, `danger`).
    - Replaced custom panels with collapsible, full-screen-enabled `bslib::card()` containers (`full_screen = TRUE`).
  - **Interactive DataTables (`DT::renderDT`)**:
    - Replaced all raw HTML `renderTable()` instances across the application with interactive, paginated, searchable, and sortable `DT::renderDT()` datatables via a standardized `create_datatable()` helper.
    - Applied to portfolio summaries, segment default tables, Wilcoxon test comparisons, Wilson confidence intervals, model benchmark comparisons, policy thresholds, monitoring scopes, feature drift tables, decile calibration tables, and applicant simulator driver attributions.
  - **High-Resolution Visualizations (`ggplot2`)**:
    - Replaced all 11 pixelated Base R graphics (`graphics::barplot`, `graphics::boxplot`, `graphics::image`, `graphics::plot`) with polished `ggplot2` charts utilizing a unified, publication-grade `theme_dashboard()`.
    - Features clear percentage and comma formatting (`scales::percent`, `scales::comma`), direct on-chart data labels, formatted axes, legend controls, and custom credit-risk palettes.

---

## Sprint 5: Completed Resolutions

- [x] **Modularize `app.R`**:
  - Decomposed the 1,390-line monolithic application orchestrator down to a sleek **154 lines** in [`app.R`](file:///home/akash/projects/SME%20Risk%20Analytics/app.R).
  - Extracted shared styling and UI helpers into [`R/ui_helpers.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/ui_helpers.R) (`page_intro`, `theme_dashboard`, `create_datatable`, `format_number`, `format_percentage`).
  - Encapsulated each major dashboard section into a clean Shiny module with isolated UI and Server namespaces under `R/`:
    - [`R/mod_overview.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_overview.R): Executive portfolio overview, SQL-backed KPI cards, risk band distribution, and filtered summaries.
    - [`R/mod_portfolio.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_portfolio.R): Segment performance analysis and quarterly application vintages.
    - [`R/mod_statistics.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_statistics.R): Statistical distributions, missingness analysis, correlation matrix, Wilcoxon rank-sum tests, and Wilson score intervals.
    - [`R/mod_models.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_models.R): Credit model benchmarks, ROC curves, calibration deciles, cumulative lift, and decision cutoff thresholds.
    - [`R/mod_monitoring.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_monitoring.R): Multi-period quarterly PSI progression, feature drift tracking, and out-of-time calibration stability.
    - [`R/mod_simulator.R`](file:///home/akash/projects/SME%20Risk%20Analytics/R/mod_simulator.R): Real-time applicant risk simulator with interactive sliders, WoE score calculation, and segregated directional risk factor attributions.
  - Eliminated global reactive crosstalk, streamlined startup loading, and ensured rock-solid database cleanup via `shiny::onStop()`.
- [x] **Automated Unit Testing Suite (`testthat`)**:
  - Integrated `testthat` into the project and registered dependencies in [`renv.lock`](file:///home/akash/projects/SME%20Risk%20Analytics/renv.lock).
  - Created master test runner [`tests/testthat.R`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat.R) and comprehensive unit tests under [`tests/testthat/`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat/):
    - [`tests/testthat/test-data_cleaning.R`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat/test-data_cleaning.R): 9 assertions verifying table counts, binary target integrity, sentinel 96/98 conversion to zero, 8 quarterly application vintages, and missing income indicator flags.
    - [`tests/testthat/test-feature_engineering.R`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat/test-feature_engineering.R): 9 assertions validating WoE preprocessor fitting, finite WoE replacements, non-negative Information Values, decoupling of raw dollar debt from DTI, and median imputation.
    - [`tests/testthat/test-db_queries.R`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat/test-db_queries.R): 20 assertions testing all parameterized SQLite query helpers (`db_get_portfolio_kpis`, `db_get_risk_band_counts`, `db_get_age_default_summary`, `db_get_segment_summary`, `db_get_vintage_performance`, `db_get_filtered_summary_table`), checking row counts, column integrity, KPI bounds, and SQL parameter filtering.
    - [`tests/testthat/test-model_calibration.R`](file:///home/akash/projects/SME%20Risk%20Analytics/tests/testthat/test-model_calibration.R): 6 assertions verifying the Bayesian odds adjustment formula, bounded probabilities, and monotonic score-to-risk-band categorization.
  - Full test execution achieves `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 44 ]` (100% pass rate).



