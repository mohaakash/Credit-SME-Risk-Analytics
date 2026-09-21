# Credit-SME Risk Analytics and Monitoring Dashboard

An R and Shiny project for exploring credit-risk patterns, comparing default-risk models, and presenting portfolio-monitoring insights through an interactive dashboard.

## Project status

The repository is initialized, `renv` is configured, and the first reproducible data-cleaning pipeline is complete. It validates the Kaggle training file, writes a cleaned CSV and SQLite database locally, and generates a data-quality report. Modeling and the Shiny application remain planned work. See the [task plan](docs/task-plan.md) for the development sequence and acceptance criteria.

## Dataset

This project uses the [Give Me Some Credit dataset on Kaggle](https://www.kaggle.com/datasets/lihxlhx/give-me-some-credit), based on the original [Give Me Some Credit competition](https://www.kaggle.com/c/GiveMeSomeCredit/data).

The dataset contains borrower-level credit information and the target `SeriousDlqin2yrs`, which indicates serious financial distress within two years. It does not contain a complete SME application funnel, application dates, processing stages, industry, geography, or loan amount fields.

The downloaded files are stored in `data/raw/` and intentionally ignored by Git. Do not commit confidential, restricted, or personally identifiable financial data.

## Planned capabilities

- Data-quality profiling and exploratory analysis
- SQLite-backed KPI and portfolio queries
- Interpretable logistic-regression credit-risk model
- Random Forest or XGBoost comparison model
- ROC-AUC, PR-AUC, KS, lift, calibration, and threshold analysis
- Shiny pages for management overview, portfolio performance, statistical analysis, and model evaluation
- Applicant risk simulator for demonstration purposes
- Model-drift, calibration, and data-quality monitoring

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

The project will later include the R dependency setup and data-preparation commands. Until then, use [docs/task-plan.md](docs/task-plan.md) as the source of truth for the next implementation steps.

### Restore the R environment and run the first pipeline

The project uses `renv` to record package versions. From the repository root:

```bash
Rscript -e 'install.packages("renv", repos = "https://cloud.r-project.org")'
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript R/data_cleaning.R
```

The pipeline expects the raw files in `data/raw/` and produces ignored local artifacts under `data/processed/` and `reports/generated/`. The tracked summary is [reports/data-quality-report.md](reports/data-quality-report.md). Initial KPI queries are in [sql/kpi_queries.sql](sql/kpi_queries.sql).

## Responsible use

This is an educational and portfolio demonstration. Model outputs and risk bands must not be used as production lending decisions. The project will document data limitations, leakage risks, class imbalance, fairness considerations, and the difference between analytical recommendations and validated banking policy.

Any synthetic application-funnel data will be stored separately and explicitly labelled as synthetic; it must not be presented as real banking data.
