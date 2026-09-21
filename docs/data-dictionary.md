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

## Known source limitations

- The data dictionary describes borrower-level credit information, not an SME application process.
- There is no application date, approval/rejection stage, loan amount, industry, or geography.
- Missing income and dependent counts are part of the source data and require an explicit modeling treatment.
- The source contains extreme ratio values and delinquency counts of `96` and `98`; the pipeline flags these observations rather than treating them as ordinary values.
