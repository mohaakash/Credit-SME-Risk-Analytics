# Credit-SME Risk Analytics and Monitoring Dashboard

## Project objective

Build an R and Shiny application for analyzing loan applications, monitoring loan portfolio performance, and developing an interpretable credit-risk model.

The project is designed to demonstrate capability in:

- R-based data cleaning and exploratory analysis
- SQL-based data extraction
- Statistical analysis and inference
- Credit-scoring model development
- Machine-learning model evaluation
- Interactive Shiny dashboards
- Business recommendations for credit-policy decisions

## Suggested data

Use a public credit-risk dataset such as:

- Home Credit Default Risk
- Give Me Some Credit
- German Credit

If the selected dataset does not contain application-stage information, create a clearly labelled synthetic application-funnel table. Synthetic fields must not be presented as real banking data.

## Core analytical questions

1. What patterns distinguish approved, rejected, and defaulted applications?
2. Which customer, loan, or financial characteristics are associated with higher default risk?
3. Where are the largest drop-offs in the application process?
4. How does portfolio performance change across customer segments and loan vintages?
5. Which model provides the best balance of predictive performance and interpretability?
6. How can the analysis support credit-policy and monitoring decisions?

## Shiny dashboard pages

### 1. Management overview

- Total applications
- Approval and rejection rates
- Average requested and approved loan amounts
- Default rate
- Risk-band distribution
- Date and segment filters

### 2. Application funnel

- Applications by processing stage
- Approval rate by customer segment
- Rejection reasons
- Processing-time trends, if available
- Stage-to-stage conversion rates

### 3. Portfolio performance

- Default and delinquency rates
- Risk by income, industry, geography, loan size, and tenure
- Vintage or cohort analysis
- Monthly performance trends
- Portfolio concentration by risk segment

### 4. Statistical analysis

- Distribution and outlier analysis
- Missing-value analysis
- Correlation analysis
- Confidence intervals
- Chi-square tests for categorical variables
- Group comparisons for defaulted and non-defaulted borrowers
- Logistic-regression coefficient interpretation

### 5. Credit-scoring model

- Interpretable logistic-regression scorecard
- Random Forest or XGBoost comparison
- ROC-AUC and PR-AUC
- KS statistic and lift by risk decile
- Brier score and calibration plot
- Confusion matrix at selected policy thresholds
- Risk bands: low, medium, and high

### 6. Applicant risk simulator

- Input applicant and loan characteristics
- Estimate probability of default
- Display the predicted risk band
- Show the main factors influencing the prediction
- Explain that the result is for demonstration and not a production lending decision

### 7. Model monitoring

- Prediction distribution over time
- Population Stability Index (PSI)
- Feature drift
- Calibration tracking
- Model-performance trends
- Data-quality warnings

## Recommended technology stack

### R and analysis

- `tidyverse`
- `data.table`
- `ggplot2`
- `plotly`
- `tidymodels`
- `glmnet`
- `ranger`
- `xgboost`
- `scorecard`, or custom Weight of Evidence and Information Value functions

### SQL and data storage

- `DBI`
- `RSQLite` for a self-contained demo, or PostgreSQL for a database-backed version
- SQL queries for filtering, aggregation, KPI calculation, and feature preparation

### Shiny application

- `shiny`
- `bslib`
- `DT`
- `plotly`

## Modeling approach

1. Profile the data and document data-quality issues.
2. Create a reproducible cleaning and feature-engineering pipeline.
3. Split the data using a time-based split where dates are available; otherwise use a stratified split.
4. Establish logistic regression as the interpretable baseline.
5. Apply binning, Weight of Evidence, and Information Value analysis where appropriate.
6. Compare the baseline with Random Forest or XGBoost.
7. Evaluate discrimination, calibration, lift, and threshold-based performance.
8. Select a policy threshold based on business trade-offs rather than accuracy alone.
9. Document model limitations, class imbalance, data leakage risks, and fairness considerations.

## Business outputs

The final report should include recommendations such as:

- Customer segments requiring additional verification
- Risk bands suitable for manual review
- Application stages with unusually high rejection or drop-off rates
- Portfolio segments requiring closer monitoring
- Features that may be useful for future credit-policy analysis

Recommendations must be supported by the analysis and should not be presented as actual banking policy without appropriate validation.

## Repository structure

```text
credit-sme-risk-analytics/
├── app.R
├── R/
│   ├── data_cleaning.R
│   ├── feature_engineering.R
│   ├── statistical_analysis.R
│   ├── train_models.R
│   └── model_monitoring.R
├── data/
│   ├── raw/
│   └── processed/
├── sql/
│   └── kpi_queries.sql
├── models/
├── reports/
├── screenshots/
├── README.md
└── renv.lock
```

Do not commit restricted, confidential, or personally identifiable financial data.

## Portfolio deliverables

- Working Shiny application
- Reproducible data-preparation scripts
- SQL queries for KPI and portfolio analysis
- Model-training and evaluation scripts
- Data dictionary
- Dashboard screenshots or a short demo video
- README explaining the business findings
- Section titled `Credit-policy recommendations`
- Limitations and responsible-use statement

## Suggested development phases

### Phase 1: Data and exploratory analysis

- Select and document the dataset
- Build the data dictionary
- Load the data into SQLite or PostgreSQL
- Perform cleaning, exploratory analysis, and statistical tests

### Phase 2: Credit-risk modeling

- Engineer features
- Train the logistic-regression baseline
- Train one tree-based model
- Evaluate discrimination, calibration, lift, and risk segmentation

### Phase 3: Shiny dashboard

- Build the management overview
- Add application-funnel and portfolio pages
- Add model evaluation and applicant simulation pages
- Add filters, tables, and interactive charts

### Phase 4: Documentation and presentation

- Add model-monitoring analysis
- Write business recommendations
- Add screenshots and a short demo
- Document limitations and responsible use
- Publish the project repository

## CV bullets after completion

After completing and validating the project, the experience could be described as:

> Developed an R Shiny dashboard for monitoring loan application funnels, portfolio risk, approval rates, and default trends using interactive filters and management KPIs.

> Built and compared interpretable logistic-regression and tree-based credit-risk models, evaluating ROC-AUC, KS statistic, lift, calibration, and probability of default.

> Applied statistical analysis, risk segmentation, feature engineering, and model-monitoring techniques to identify borrower segments associated with higher default risk.

Only include metrics and results that are actually achieved in the completed project.
