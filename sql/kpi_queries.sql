-- Reusable Analytical KPI queries for data/processed/give_me_some_credit.sqlite
-- Used by the Shiny dashboard and analytical reports.

-- 1. Portfolio size, default rate, mean predicted risk, and high-risk concentration
SELECT
  COUNT(*) AS borrower_count,
  SUM(CASE WHEN serious_dlqin2yrs = 1 THEN 1 ELSE 0 END) AS default_count,
  AVG(serious_dlqin2yrs) AS default_rate,
  AVG(predicted_risk) AS mean_predicted_risk,
  SUM(CASE WHEN risk_band IN ('High', 'Very high') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS high_risk_rate
FROM training_clean;

-- 2. Quarterly Vintage Cohort Performance & Tracking
SELECT
  vintage_quarter,
  COUNT(*) AS borrower_count,
  SUM(serious_dlqin2yrs) AS default_count,
  ROUND(AVG(serious_dlqin2yrs) * 100, 2) AS default_rate_pct,
  ROUND(AVG(revolving_utilization_of_unsecured_lines), 3) AS mean_utilization,
  ROUND(AVG(predicted_risk) * 100, 2) AS mean_predicted_risk_pct
FROM training_clean
GROUP BY vintage_quarter
ORDER BY vintage_quarter;

-- 3. Risk-Band Distribution and Realized Default Rates
SELECT
  risk_band,
  COUNT(*) AS borrower_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM training_clean), 2) AS portfolio_share_pct,
  SUM(serious_dlqin2yrs) AS default_count,
  ROUND(AVG(serious_dlqin2yrs) * 100, 2) AS default_rate_pct,
  ROUND(AVG(predicted_risk) * 100, 2) AS mean_predicted_risk_pct
FROM training_clean
GROUP BY risk_band
ORDER BY risk_band;

-- 4. Segment Analysis: Age Band Default Rates
SELECT
  age_band,
  COUNT(*) AS borrower_count,
  SUM(serious_dlqin2yrs) AS default_count,
  ROUND(AVG(serious_dlqin2yrs) * 100, 2) AS default_rate_pct,
  ROUND(AVG(predicted_risk) * 100, 2) AS mean_predicted_risk_pct
FROM training_clean
GROUP BY age_band
ORDER BY age_band;

-- 5. Segment Analysis: Delinquency History (90+ Days Late)
SELECT
  delinquency_90_status,
  COUNT(*) AS borrower_count,
  SUM(serious_dlqin2yrs) AS default_count,
  ROUND(AVG(serious_dlqin2yrs) * 100, 2) AS default_rate_pct
FROM training_clean
GROUP BY delinquency_90_status
ORDER BY delinquency_90_status;

-- 6. Missingness KPIs
SELECT
  variable,
  missing_count,
  row_count,
  ROUND(missing_pct * 100, 2) AS missing_pct
FROM missingness
WHERE missing_count > 0
ORDER BY missing_pct DESC;

-- 7. Data-Quality Flag Summary
SELECT
  metric,
  value
FROM quality_summary
ORDER BY metric;
