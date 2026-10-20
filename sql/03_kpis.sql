-- Executive KPI queries
-- Run in psql:  psql -d voiceiq -f sql/03_kpis.sql

SET search_path TO voiceiq, public;

-- 1. Customers and churn rate
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM customers;

-- 2. Overall NPS and CSAT
-- NPS = % Promoters (9-10) - % Detractors (0-6)
SELECT
    COUNT(*) AS responses,
    ROUND(100.0 * SUM(CASE WHEN nps_category = 'Promoter'  THEN 1 ELSE 0 END) / COUNT(*), 1) AS promoter_pct,
    ROUND(100.0 * SUM(CASE WHEN nps_category = 'Detractor' THEN 1 ELSE 0 END) / COUNT(*), 1) AS detractor_pct,
    ROUND(100.0 * (SUM(CASE WHEN nps_category = 'Promoter'  THEN 1 ELSE 0 END)
                 - SUM(CASE WHEN nps_category = 'Detractor' THEN 1 ELSE 0 END)) / COUNT(*), 1) AS nps,
    ROUND(AVG(csat_score), 2) AS avg_csat
FROM surveys;

-- 3. NPS by quarter (is it going up or down?)
SELECT
    DATE_TRUNC('quarter', survey_date)::date AS quarter,
    COUNT(*) AS responses,
    ROUND(100.0 * (SUM(CASE WHEN nps_category = 'Promoter'  THEN 1 ELSE 0 END)
                 - SUM(CASE WHEN nps_category = 'Detractor' THEN 1 ELSE 0 END)) / COUNT(*), 1) AS nps,
    ROUND(AVG(csat_score), 2) AS avg_csat
FROM surveys
GROUP BY DATE_TRUNC('quarter', survey_date)
ORDER BY quarter;

-- 4. NPS by customer segment
SELECT
    c.customer_segment,
    COUNT(*) AS responses,
    ROUND(100.0 * (SUM(CASE WHEN s.nps_category = 'Promoter'  THEN 1 ELSE 0 END)
                 - SUM(CASE WHEN s.nps_category = 'Detractor' THEN 1 ELSE 0 END)) / COUNT(*), 1) AS nps,
    ROUND(AVG(s.csat_score), 2) AS avg_csat
FROM surveys s
JOIN customers c ON c.customer_id = s.customer_id
GROUP BY c.customer_segment
ORDER BY nps DESC;

-- 5. NPS by subscription plan
SELECT
    c.subscription_plan,
    COUNT(*) AS responses,
    ROUND(100.0 * (SUM(CASE WHEN s.nps_category = 'Promoter'  THEN 1 ELSE 0 END)
                 - SUM(CASE WHEN s.nps_category = 'Detractor' THEN 1 ELSE 0 END)) / COUNT(*), 1) AS nps
FROM surveys s
JOIN customers c ON c.customer_id = s.customer_id
GROUP BY c.subscription_plan
ORDER BY nps DESC;

-- 6. Churn rate and revenue by subscription plan
SELECT
    subscription_plan,
    COUNT(*) AS customers,
    ROUND(AVG(monthly_revenue), 2) AS avg_monthly_revenue,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM customers
GROUP BY subscription_plan
ORDER BY churn_rate_pct DESC;

-- 7. Support ticket summary
SELECT
    COUNT(*) AS total_tickets,
    SUM(CASE WHEN status IN ('Open', 'In Progress') THEN 1 ELSE 0 END) AS open_tickets,
    SUM(CASE WHEN status IN ('Resolved', 'Closed')  THEN 1 ELSE 0 END) AS resolved_tickets,
    ROUND(AVG(resolution_time), 1) AS avg_resolution_hours,   -- AVG skips NULLs (open tickets)
    ROUND(AVG(csat_rating), 2) AS avg_ticket_csat
FROM support_tickets;
