# Give Me Some Credit — Data Dictionary

Source: `data/raw/Data Dictionary.xls`, Sheet1.

| Variable | Description | Type in source |
| --- | --- | --- |
| `SeriousDlqin2yrs` | Person experienced 90 days past due delinquency or worse | Y/N |
| `RevolvingUtilizationOfUnsecuredLines` | Total balance on credit cards and personal lines of credit, excluding real estate and installment debt, divided by the sum of credit limits | Percentage |
| `age` | Age of borrower in years | Integer |
| `NumberOfTime30-59DaysPastDueNotWorse` | Number of times borrower has been 30–59 days past due but no worse in the last 2 years | Integer |
| `DebtRatio` | Monthly debt payments, alimony, and living costs divided by monthly gross income | Percentage |
| `MonthlyIncome` | Monthly income | Real |
| `NumberOfOpenCreditLinesAndLoans` | Number of open installment loans and lines of credit | Integer |
| `NumberOfTimes90DaysLate` | Number of times borrower has been 90 days or more past due | Integer |
| `NumberRealEstateLoansOrLines` | Number of mortgage and real-estate loans, including home-equity lines of credit | Integer |
| `NumberOfTime60-89DaysPastDueNotWorse` | Number of times borrower has been 60–89 days past due but no worse in the last 2 years | Integer |
| `NumberOfDependents` | Number of dependents in the family, excluding the borrower | Integer |

## Project naming

The cleaning pipeline converts source names to snake_case. The target becomes `serious_dlqin2yrs`. The first unnamed CSV column is interpreted as the borrower identifier and becomes `id`.

## Target definition

`serious_dlqin2yrs = 1` indicates the borrower experienced serious delinquency within the target period. The training file contains the target; the test file does not and is not used for training or quality-rate estimates.

## Scope and Known Limitations

- **Consumer credit scope**: The data describes consumer retail credit card and line-of-credit borrowers, not commercial SME entities. Features reflect individual borrower demographics and personal debt history.
- **No application funnel or timestamps**: There is no application date, approval/rejection stage, requested loan amount, industry code, or geography in the public Kaggle dataset.
- **`DebtRatio` dual-definition quirk**: In the raw dataset, when `MonthlyIncome` is missing, `DebtRatio` actually represents the borrower's total monthly debt obligations in raw dollars (median ~$1,159, with values reaching >$300,000). When `MonthlyIncome` is observed, `DebtRatio` is the conventional debt-to-income ratio. The modeling pipeline cleanly separates these by treating missing income DTI as NA (imputed with the training median DTI of ~0.296) and capping observed DTI at 10.0 to prevent outlier distortion.
- **Missing income and dependent counts**: Missing values are present in ~19.8% of income records and ~2.6% of dependent counts, handled via training median imputation and explicit missingness indicators.
- **Sentinel delinquency values**: Delinquency counts of `96` and `98` are sentinel codes (representing missing or undetermined delinquency status) rather than literal counts; the pipeline converts them to missing values while retaining sentinel flags.
