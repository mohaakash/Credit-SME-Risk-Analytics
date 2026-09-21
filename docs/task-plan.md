# Credit-SME Risk Analytics Dashboard — Task Plan

## Current status

- Project brief: `docs/credit-sme-risk-analytics-shiny.md`
- Dataset downloaded on 2026-09-21 into `data/raw/`.
- Source mirror: [Give Me Some Credit on Kaggle](https://www.kaggle.com/datasets/lihxlhx/give-me-some-credit).
- Original competition: [Give Me Some Credit](https://www.kaggle.com/c/GiveMeSomeCredit/data).
- Downloaded files:
  - `Data Dictionary.xls`
  - `cs-training.csv`
  - `cs-test.csv`
  - `sampleEntry.csv`
- The direct competition API requires Kaggle authentication; the public Kaggle mirror was used for this local download.
- `renv` is initialized with a lockfile for the first data-preparation slice.
- The first cleaning run produced a validation report and SQLite database locally; generated data artifacts remain Git-ignored.
- Phase 2 statistical analysis now produces descriptive comparisons, confidence intervals, segment rates, chi-square tests, correlations, plots, and a preliminary logistic interpretation report.
- Phase 3 has a leakage-safe stratified split, raw logistic baseline, training-only WoE/IV candidate, CART benchmark, class-balanced Random Forest benchmark, XGBoost benchmark, held-out metrics, threshold trade-offs, calibration, lift, leakage checks, class-balance diagnostics, segment stability summaries, and fairness proxy diagnostics.
- Phase 4 now has a runnable Shiny dashboard with management overview, portfolio performance, statistical analysis, credit-model evaluation, and an applicant risk simulator.

Raw files are intentionally ignored by Git. The source URL, file names, and checksums must remain documented so the data can be restored reproducibly.

## Scope for the first release

Build a reproducible R/Shiny portfolio-risk demonstration around the Kaggle dataset. The first release will focus on:

1. Data quality and exploratory analysis.
2. A SQLite-backed analytical dataset.
3. An interpretable logistic-regression default model.
4. One tree-based comparison model.
5. A Shiny dashboard with management, portfolio, statistical-analysis, model, and demonstration simulator pages.
6. Responsible-use documentation and evidence-based recommendations.

The application-funnel page, application dates, processing times, industry, geography, and loan amount are not present in the downloaded dataset. They are out of scope until a defensible source is selected. If synthetic funnel data is added later, it must be stored separately and labelled as synthetic in the UI and documentation.

## Phase 0 — Project foundation

### Tasks

- [x] Initialize `renv` for the R project.
- [x] Add the initial package manifest for data work and SQL-backed analysis.
- [x] Confirm the repository structure:
  - `R/`
  - `data/raw/`
  - `data/processed/`
  - `sql/`
  - `models/`
  - `reports/`
  - `screenshots/`
- [x] Add a README with setup, data acquisition, run instructions, and responsible-use language.
- [x] Record dataset provenance and checksums.

### Acceptance criteria

- A new user can install the documented R dependencies and run the project setup instructions.
- No raw or confidential financial data is required to be committed to the repository.

## Phase 1 — Data ingestion and quality profiling

### Tasks

- [x] Read and translate `Data Dictionary.xls` into `docs/data-dictionary.md`.
- [x] Create `R/data_cleaning.R` with a reproducible import function.
- [x] Standardize column names and preserve the original Kaggle names in the data dictionary.
- [x] Validate row counts, column counts, data types, target values, duplicate IDs, and impossible values.
- [x] Profile missingness, zero values, extreme values, and suspicious sentinel values.
- [x] Define a documented treatment for missing monthly income and dependents.
- [x] Write the cleaned dataset to `data/processed/`.
- [x] Load the cleaned data into SQLite.
- [x] Add `sql/kpi_queries.sql` for row counts, default rates, segment summaries, and missingness KPIs.

### Acceptance criteria

- The cleaning pipeline can be rerun from raw files without manual edits.
- Every transformation is documented and traceable to a source column.
- The target is clearly defined as `SeriousDlqin2yrs` and no test labels are used in training.
- A validation summary is produced before modeling.

## Phase 2 — Exploratory and statistical analysis

### Tasks

- [x] Create `R/statistical_analysis.R`.
- [x] Compare defaulted and non-defaulted borrowers across all usable variables.
- [x] Produce distributions, outlier summaries, and missing-value visuals.
- [x] Add correlation analysis for numeric variables.
- [x] Add confidence intervals for default rates and group comparisons.
- [x] Add chi-square tests for binned/categorical variables where appropriate.
- [x] Add an initial logistic-regression interpretation report.
- [x] Save reproducible figures and summary tables under `reports/generated/`.

### Acceptance criteria

- Each statistical test states its comparison, assumptions, and interpretation.
- Visualizations include sample sizes and avoid implying causation.
- Findings are separated from business recommendations.

## Phase 3 — Credit-risk modeling

### Tasks

- [x] Create `R/feature_engineering.R`.
- [x] Use a stratified split because this dataset does not provide a usable application date.
- [x] Establish logistic regression as the baseline.
- [x] Add training-only binning/Weight of Evidence/Information Value and validate the WoE logistic candidate on the held-out test set.
- [x] Train a first CART tree-based comparison model as a runnable benchmark.
- [x] Add a reproducible Random Forest comparison with fixed settings and class-balanced bootstrap samples.
- [x] Add a fixed-parameter XGBoost comparison with training-derived class weighting.
- [x] Create `R/train_models.R` with fixed seeds and saved preprocessing.
- [x] Evaluate ROC-AUC, PR-AUC, KS, lift by risk decile, Brier score, calibration, and threshold metrics.
- [x] Produce demonstration threshold trade-offs with explicit false-negative/false-positive metrics; do not select a lending-policy threshold.
- [x] Save model objects and evaluation summaries under `models/` and `reports/generated/`.
- [x] Check for leakage, class imbalance, unstable segments, and possible fairness concerns using available proxy segments.

### Acceptance criteria

- All benchmark candidates are evaluated on the same held-out data.
- The selected model is justified using discrimination, calibration, interpretability, and policy trade-offs.
- Risk bands are reproducible and labelled as demonstration bands, not lending policy.
- No unvalidated accuracy claim is used as the primary success measure.

## Phase 4 — Shiny dashboard

### Tasks

- [x] Create `app.R` with a clear application startup check.
- [x] Build the Management Overview page:
  - Default rate
  - Borrower count
  - Risk-band distribution
  - Segment filters
- [x] Build the Portfolio Performance page using the available borrower attributes.
- [x] Build the Statistical Analysis page with missingness, distributions, and group comparisons.
- [x] Build the Credit-Scoring Model page with model comparison, calibration, lift, and threshold results.
- [x] Add the Applicant Risk Simulator using the saved preprocessing and logistic model.
- [x] Add a visible demonstration-only and responsible-use disclaimer.
- [ ] Add the Application Funnel page only after deciding whether to use a separate synthetic table.

### Acceptance criteria

- `shiny::runApp()` starts successfully from a clean checkout after setup.
- Every KPI is calculated from the processed data or saved model artifacts.
- Filters update all relevant outputs consistently.
- The simulator uses the same preprocessing as model training.

## Phase 5 — Monitoring and presentation

### Tasks

- [ ] Create `R/model_monitoring.R`.
- [ ] Add prediction-distribution summaries and a demonstration PSI workflow.
- [ ] Add feature-drift and calibration checks where comparison periods are available.
- [ ] Clearly mark any simulated monitoring periods as synthetic.
- [ ] Write the final README business findings.
- [ ] Add a section titled `Credit-policy recommendations`.
- [ ] Add limitations, responsible-use, leakage, dataset-representativeness, and fairness statements.
- [ ] Capture dashboard screenshots or a short demo video.

### Acceptance criteria

- Monitoring outputs distinguish real observations from simulated examples.
- Recommendations are traceable to analysis outputs and are not presented as actual banking policy.
- The project can be understood and run without relying on undocumented local state.

## Phase 4 implementation notes

- The dashboard uses only fields and saved artifacts produced by the current pipelines; it does not fabricate application dates, loan amounts, industries, geography, or processing stages.
- The risk bands are percentile-based demonstrations from the saved logistic model and are not lending-policy thresholds.
- The visual system uses an organic earth-tone palette, rounded analytical cards, humanist typography, and a restrained grain texture to keep the dashboard approachable while retaining analytical clarity.
- The current Shiny runtime uses base Shiny tables and plots plus `bslib`; no optional browser-side chart dependency is required.

## Immediate next sprint

1. [x] Inspect the Excel data dictionary and verify the four downloaded files.
2. [x] Initialize the R project and `renv`.
3. [x] Implement the raw-data validation and cleaning pipeline.
4. [x] Produce the first data-quality report.
5. [x] Load the cleaned training data into SQLite and write the first KPI queries.
6. [x] Review the findings before selecting final features and model scope.
7. [x] Implement the first dashboard slice and verify the Shiny server outputs.
8. [x] Add package-backed Random Forest and XGBoost benchmarks plus training-only WoE/IV screening.
9. [ ] Add model monitoring and decide whether a separately labelled synthetic application-funnel table is justified.

## Data provenance checksums

These checksums describe the files downloaded during initialization:

```text
d388d6b11ed63fee95432048187c8c064b8ca38e40d7e8aab9edd36af240b092  data/raw/Data Dictionary.xls
bab363a2a807218d32a51f5fc9668b8be7977795065edd386abc8546abaa5b78  data/raw/cs-test.csv
1bd46da486a5708c58c7b01a034fae2a13b327f6f7b62ea7ba4fe3b5824b24ac  data/raw/cs-training.csv
578b4b01d0f6ed7f97f1988afff0c41194e72bf4b25707119903d4de3dc1dcea  data/raw/sampleEntry.csv
```
