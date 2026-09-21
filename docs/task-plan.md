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

Raw files are intentionally ignored by Git. The source URL, file names, and checksums must remain documented so the data can be restored reproducibly.

## Scope for the first release

Build a reproducible R/Shiny portfolio-risk demonstration around the Kaggle dataset. The first release will focus on:

1. Data quality and exploratory analysis.
2. A SQLite-backed analytical dataset.
3. An interpretable logistic-regression default model.
4. One tree-based comparison model.
5. A Shiny dashboard with management, portfolio, statistical-analysis, and model pages.
6. Responsible-use documentation and evidence-based recommendations.

The application-funnel page, application dates, processing times, industry, geography, and loan amount are not present in the downloaded dataset. They are out of scope until a defensible source is selected. If synthetic funnel data is added later, it must be stored separately and labelled as synthetic in the UI and documentation.

## Phase 0 — Project foundation

### Tasks

- [ ] Create the R project entry point and initialize `renv`.
- [ ] Add the package manifest for data work, SQL, modeling, and Shiny.
- [ ] Confirm the repository structure:
  - `R/`
  - `data/raw/`
  - `data/processed/`
  - `sql/`
  - `models/`
  - `reports/`
  - `screenshots/`
- [ ] Add a README with setup, data acquisition, run instructions, and responsible-use language.
- [ ] Record dataset provenance and checksums.

### Acceptance criteria

- A new user can install the documented R dependencies and run the project setup instructions.
- No raw or confidential financial data is required to be committed to the repository.

## Phase 1 — Data ingestion and quality profiling

### Tasks

- [ ] Read and translate `Data Dictionary.xls` into `docs/data-dictionary.md`.
- [ ] Create `R/data_cleaning.R` with a reproducible import function.
- [ ] Standardize column names and preserve the original Kaggle names in the data dictionary.
- [ ] Validate row counts, column counts, data types, target values, duplicate IDs, and impossible values.
- [ ] Profile missingness, zero values, extreme values, and suspicious sentinel values.
- [ ] Define a documented treatment for missing monthly income and dependents.
- [ ] Write the cleaned dataset to `data/processed/`.
- [ ] Load the cleaned data into SQLite.
- [ ] Add `sql/kpi_queries.sql` for row counts, default rates, segment summaries, and missingness KPIs.

### Acceptance criteria

- The cleaning pipeline can be rerun from raw files without manual edits.
- Every transformation is documented and traceable to a source column.
- The target is clearly defined as `SeriousDlqin2yrs` and no test labels are used in training.
- A validation summary is produced before modeling.

## Phase 2 — Exploratory and statistical analysis

### Tasks

- [ ] Create `R/statistical_analysis.R`.
- [ ] Compare defaulted and non-defaulted borrowers across all usable variables.
- [ ] Produce distributions, outlier summaries, and missing-value visuals.
- [ ] Add correlation analysis for numeric variables.
- [ ] Add confidence intervals for default rates and group comparisons.
- [ ] Add chi-square tests for binned/categorical variables where appropriate.
- [ ] Add an initial logistic-regression interpretation report.
- [ ] Save reproducible figures and summary tables under `reports/generated/`.

### Acceptance criteria

- Each statistical test states its comparison, assumptions, and interpretation.
- Visualizations include sample sizes and avoid implying causation.
- Findings are separated from business recommendations.

## Phase 3 — Credit-risk modeling

### Tasks

- [ ] Create `R/feature_engineering.R`.
- [ ] Use a stratified split because this dataset does not provide a usable application date.
- [ ] Establish logistic regression as the baseline.
- [ ] Add binning/Weight of Evidence/Information Value only where it improves interpretability and is validated.
- [ ] Train one tree-based comparison model: Random Forest or XGBoost.
- [ ] Create `R/train_models.R` with fixed seeds and saved preprocessing.
- [ ] Evaluate ROC-AUC, PR-AUC, KS, lift by risk decile, Brier score, calibration, and threshold metrics.
- [ ] Select demonstration thresholds using explicit false-negative/false-positive trade-offs.
- [ ] Save model objects and evaluation summaries under `models/` and `reports/generated/`.
- [ ] Check for leakage, class imbalance, unstable segments, and possible fairness concerns.

### Acceptance criteria

- Both models are evaluated on the same held-out data.
- The selected model is justified using discrimination, calibration, interpretability, and policy trade-offs.
- Risk bands are reproducible and labelled as demonstration bands, not lending policy.
- No unvalidated accuracy claim is used as the primary success measure.

## Phase 4 — Shiny dashboard

### Tasks

- [ ] Create `app.R` with a clear application startup check.
- [ ] Build the Management Overview page:
  - Default rate
  - Borrower count
  - Risk-band distribution
  - Segment filters
- [ ] Build the Portfolio Performance page using the available borrower attributes.
- [ ] Build the Statistical Analysis page with missingness, distributions, and group comparisons.
- [ ] Build the Credit-Scoring Model page with model comparison, calibration, lift, and threshold results.
- [ ] Add the Applicant Risk Simulator after the prediction pipeline is stable.
- [ ] Add a visible demonstration-only and responsible-use disclaimer.
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

## Immediate next sprint

1. Inspect the Excel data dictionary and verify the four downloaded files.
2. Initialize the R project and `renv`.
3. Implement the raw-data validation and cleaning pipeline.
4. Produce the first data-quality report.
5. Load the cleaned training data into SQLite and write the first KPI queries.
6. Review the findings before selecting final features and model scope.

Stop after the first data-quality report and SQLite load. Do not build the full dashboard or synthetic funnel until the real dataset's limitations and usable fields are confirmed.

## Data provenance checksums

These checksums describe the files downloaded during initialization:

```text
d388d6b11ed63fee95432048187c8c064b8ca38e40d7e8aab9edd36af240b092  data/raw/Data Dictionary.xls
bab363a2a807218d32a51f5fc9668b8be7977795065edd386abc8546abaa5b78  data/raw/cs-test.csv
1bd46da486a5708c58c7b01a034fae2a13b327f6f7b62ea7ba4fe3b5824b24ac  data/raw/cs-training.csv
578b4b01d0f6ed7f97f1988afff0c41194e72bf4b25707119903d4de3dc1dcea  data/raw/sampleEntry.csv
```
