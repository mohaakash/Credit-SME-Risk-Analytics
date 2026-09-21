# Credit-SME Risk Analytics and Monitoring Dashboard

An R and Shiny project for exploring credit-risk patterns, comparing default-risk models, and presenting portfolio-monitoring insights through an interactive dashboard.

## Project status

The repository is initialized, `renv` is configured, and the reproducible data-cleaning, statistical-analysis, modeling, and Shiny dashboard slices are available. The project validates the Kaggle training file, writes a cleaned CSV and SQLite database locally, generates analysis and model-evaluation reports, and serves an interactive dashboard from `app.R`. Random Forest/XGBoost comparison and model monitoring remain planned work. See the [task plan](docs/task-plan.md) for the development sequence and acceptance criteria.

## Dataset

This project uses the [Give Me Some Credit dataset on Kaggle](https://www.kaggle.com/datasets/lihxlhx/give-me-some-credit), based on the original [Give Me Some Credit competition](https://www.kaggle.com/c/GiveMeSomeCredit/data).

The dataset contains borrower-level credit information and the target `SeriousDlqin2yrs`, which indicates serious financial distress within two years. It does not contain a complete SME application funnel, application dates, processing stages, industry, geography, or loan amount fields.

The downloaded files are stored in `data/raw/` and intentionally ignored by Git. Do not commit confidential, restricted, or personally identifiable financial data.

## Available capabilities

- Data-quality profiling and exploratory analysis
- SQLite-backed KPI and portfolio queries
- Interpretable logistic-regression credit-risk model
- CART comparison model, with Random Forest/XGBoost documented as a follow-up
- ROC-AUC, PR-AUC, KS, lift, calibration, and threshold analysis
- Shiny pages for management overview, portfolio performance, statistical analysis, and model evaluation
- Applicant risk simulator for demonstration purposes

## Planned capabilities

- Model-drift, calibration, and data-quality monitoring
- Random Forest/XGBoost comparison when the package source is available
- A defensible application-funnel dataset or explicitly labelled synthetic funnel page

## Planned repository structure

```text
.
├── app.R
├── R/
├── data/
│   ├── raw/
│   └── processed/
├── sql/
├── models/
├── reports/
├── screenshots/
├── docs/
└── renv.lock
```

## Getting started

### Prerequisites

- R and RStudio or another R environment
- Internet access for installing R packages and obtaining the dataset
- Optional: Kaggle account and API credentials for reproducible CLI downloads

### Clone the repository

```bash
git clone https://github.com/mohaakash/Credit-SME-Risk-Analytics-and-Monitoring-Dashboard.git
cd Credit-SME-Risk-Analytics-and-Monitoring-Dashboard
```

### Restore the dataset

The local raw files are not part of the Git repository. Download them from Kaggle and place the extracted files in `data/raw/`:

```bash
kaggle datasets download -d lihxlhx/give-me-some-credit \
  -p data/raw --unzip
```

Use [docs/task-plan.md](docs/task-plan.md) as the source of truth for the implementation sequence and remaining work.

### Restore the R environment and run the first pipeline

The project uses `renv` to record package versions. From the repository root:

```bash
Rscript -e 'install.packages("renv", repos = "https://cloud.r-project.org")'
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript R/data_cleaning.R
Rscript R/statistical_analysis.R
Rscript R/train_models.R
```

The pipeline expects the raw files in `data/raw/` and produces ignored local artifacts under `data/processed/`, `models/`, and `reports/generated/`. The tracked summaries are [reports/data-quality-report.md](reports/data-quality-report.md), [reports/statistical-analysis-report.md](reports/statistical-analysis-report.md), and [reports/modeling-report.md](reports/modeling-report.md). Initial KPI queries are in [sql/kpi_queries.sql](sql/kpi_queries.sql).

### Run the dashboard

After the preparation commands complete, start the Shiny app from the repository root:

```bash
Rscript -e 'shiny::runApp(".", launch.browser = TRUE)'
```

The dashboard reads the cleaned SQLite data and saved model/evaluation artifacts. It includes portfolio filters, segment performance, statistical summaries, held-out model evaluation, and an applicant risk simulator using the saved preprocessing path.

## Responsible use

This is an educational and portfolio demonstration. Model outputs and risk bands must not be used as production lending decisions. The project will document data limitations, leakage risks, class imbalance, fairness considerations, and the difference between analytical recommendations and validated banking policy.

Any synthetic application-funnel data will be stored separately and explicitly labelled as synthetic; it must not be presented as real banking data.
