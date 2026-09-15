-- =============================================================================
-- VoiceIQ — Voice of Customer Analytics Platform
-- 03_kpis.sql
--
-- Purpose : Executive & product-level KPI views for the Power BI "Executive
--           Overview" and "Customer Experience" pages (Module 8).
-- Usage   : psql -d voiceiq -f sql/03_kpis.sql
--
-- Design note: every view below that needs figures from more than one fact
-- table (surveys + support_tickets, say) aggregates each fact table to the
-- target grain in its OWN CTE first, then joins the pre-aggregated CTEs.
-- Joining two fact tables directly to a shared dimension before aggregating
-- causes row fan-out (a customer with 5 surveys and 3 tickets would produce
-- 15 joined rows), silently inflating every AVG()/SUM() downstream — a
-- classic and easy-to-miss correctness bug in exactly this kind of query.
-- =============================================================================

SET search_path TO voiceiq, public;

-- -----------------------------------------------------------------------------
-- 1. EXECUTIVE KPI TABLE
-- One-row snapshot for the top KPI cards on the Executive Overview page.
-- Uses each customer's MOST RECENT survey (DISTINCT ON) so "current NPS/CSAT"
-- reflects where things stand today, not a blended all-time average.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_executive_kpis AS
WITH latest_survey AS (
    SELECT DISTINCT ON (customer_id)
        customer_id, nps_score, nps_category, csat_score
    FROM surveys
    ORDER BY customer_id, survey_date DESC
),
ticket_stats AS (
    SELECT
        COUNT(*) FILTER (WHERE status IN ('Open', 'In Progress'))  AS open_tickets,
        COUNT(*) FILTER (WHERE status IN ('Resolved', 'Closed'))   AS resolved_tickets,
        ROUND(AVG(resolution_time) FILTER (WHERE resolution_time IS NOT NULL)::numeric, 1) AS avg_resolution_hours,
        ROUND(AVG(csat_rating) FILTER (WHERE csat_rating IS NOT NULL)::numeric, 2) AS avg_transactional_csat
    FROM support_tickets
)
SELECT
    (SELECT COUNT(*) FROM customers)                          AS total_customers,
    (SELECT COUNT(*) FROM customers WHERE is_churned)         AS churned_customers,
    ROUND(100.0 * (SELECT COUNT(*) FROM customers WHERE is_churned)
                 / NULLIF((SELECT COUNT(*) FROM customers), 0), 2)       AS churn_rate_pct,
    ROUND(100.0 * AVG(CASE ls.nps_category
                           WHEN 'Promoter'  THEN 1
                           WHEN 'Detractor' THEN -1
                           ELSE 0
                       END), 1)                                          AS current_nps,
    ROUND(AVG(ls.csat_score)::numeric, 2)                                AS current_relationship_csat,
    ts.avg_transactional_csat,
    ts.open_tickets,
    ts.resolved_tickets,
    ts.avg_resolution_hours
FROM latest_survey ls
CROSS JOIN ticket_stats ts
GROUP BY ts.open_tickets, ts.resolved_tickets, ts.avg_resolution_hours, ts.avg_transactional_csat;

COMMENT ON VIEW vw_executive_kpis IS 'Single-row KPI snapshot for the Executive Overview dashboard page.';

-- -----------------------------------------------------------------------------
-- 2. MONTHLY NPS TREND
-- DATE_TRUNC for monthly buckets, LAG for month-over-month change, a window
-- frame for a trailing 3-month moving average — the standard way to smooth a
-- noisy monthly NPS series for an executive line chart.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_monthly_nps_trend AS
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', survey_date)::date AS survey_month,
        COUNT(*) AS responses,
        ROUND(100.0 * AVG(CASE nps_category
                               WHEN 'Promoter'  THEN 1
                               WHEN 'Detractor' THEN -1
                               ELSE 0
                           END), 1) AS nps_score,
        ROUND(AVG(csat_score)::numeric, 2) AS avg_csat
    FROM surveys
    GROUP BY 1
)
SELECT
    survey_month,
    responses,
    nps_score,
    avg_csat,
    ROUND(AVG(nps_score) OVER (
        ORDER BY survey_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1) AS nps_3mo_moving_avg,
    nps_score - LAG(nps_score) OVER (ORDER BY survey_month) AS nps_mom_change
FROM monthly
ORDER BY survey_month;

COMMENT ON VIEW vw_monthly_nps_trend IS 'Monthly NPS with 3-month moving average and month-over-month delta.';

-- -----------------------------------------------------------------------------
-- 3. AVERAGE CSAT BY COUNTRY
-- Fact tables pre-aggregated separately (see file header), then joined and
-- ranked so the dashboard can call out best/worst-performing markets.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_csat_by_country AS
WITH survey_agg AS (
    SELECT
        c.country,
        COUNT(DISTINCT c.customer_id) AS customers,
        AVG(s.csat_score) AS avg_relationship_csat
    FROM customers c
    JOIN surveys s ON s.customer_id = c.customer_id
    GROUP BY c.country
),
ticket_agg AS (
    SELECT
        c.country,
        AVG(t.csat_rating) AS avg_transactional_csat
    FROM customers c
    JOIN support_tickets t ON t.customer_id = c.customer_id
    WHERE t.csat_rating IS NOT NULL
    GROUP BY c.country
)
SELECT
    sa.country,
    sa.customers,
    ROUND(sa.avg_relationship_csat::numeric, 2) AS avg_relationship_csat,
    ROUND(ta.avg_transactional_csat::numeric, 2) AS avg_transactional_csat,
    RANK() OVER (ORDER BY sa.avg_relationship_csat DESC) AS csat_rank
FROM survey_agg sa
LEFT JOIN ticket_agg ta ON ta.country = sa.country
ORDER BY avg_relationship_csat DESC;

COMMENT ON VIEW vw_csat_by_country IS 'Relationship and transactional CSAT by customer country, ranked best to worst.';

-- -----------------------------------------------------------------------------
-- 4. CUSTOMER SATISFACTION BY SUBSCRIPTION PLAN
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_satisfaction_by_plan AS
WITH survey_agg AS (
    SELECT
        c.subscription_plan,
        COUNT(DISTINCT c.customer_id) AS customers,
        ROUND(100.0 * AVG(CASE s.nps_category
                               WHEN 'Promoter'  THEN 1
                               WHEN 'Detractor' THEN -1
                               ELSE 0
                           END), 1) AS nps_score,
        ROUND(AVG(s.csat_score)::numeric, 2) AS avg_relationship_csat
    FROM customers c
    JOIN surveys s ON s.customer_id = c.customer_id
    GROUP BY c.subscription_plan
),
plan_agg AS (
    SELECT
        subscription_plan,
        ROUND(100.0 * AVG(is_churned::int), 2) AS churn_rate_pct,
        ROUND(AVG(monthly_revenue)::numeric, 2) AS avg_mrr
    FROM customers
    GROUP BY subscription_plan
)
SELECT
    sa.subscription_plan,
    sa.customers,
    pa.avg_mrr,
    pa.churn_rate_pct,
    sa.nps_score,
    sa.avg_relationship_csat,
    RANK() OVER (ORDER BY sa.nps_score DESC) AS nps_rank
FROM survey_agg sa
JOIN plan_agg pa USING (subscription_plan)
ORDER BY sa.nps_score DESC;

COMMENT ON VIEW vw_satisfaction_by_plan IS 'NPS, CSAT, churn rate and MRR by subscription plan tier.';

-- -----------------------------------------------------------------------------
-- 5. CUSTOMER SEGMENT COMPARISON
-- SMB vs. Mid-Market vs. Enterprise, side by side on every headline metric.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_segment_comparison AS
WITH base_agg AS (
    SELECT
        customer_segment,
        COUNT(*) AS customers,
        ROUND(AVG(monthly_revenue)::numeric, 2) AS avg_mrr,
        ROUND(100.0 * AVG(is_churned::int), 2) AS churn_rate_pct
    FROM customers
    GROUP BY customer_segment
),
survey_agg AS (
    SELECT
        c.customer_segment,
        ROUND(100.0 * AVG(CASE s.nps_category
                               WHEN 'Promoter'  THEN 1
                               WHEN 'Detractor' THEN -1
                               ELSE 0
                           END), 1) AS nps_score,
        ROUND(AVG(s.csat_score)::numeric, 2) AS avg_relationship_csat
    FROM customers c
    JOIN surveys s ON s.customer_id = c.customer_id
    GROUP BY c.customer_segment
),
ticket_agg AS (
    SELECT
        c.customer_segment,
        COUNT(t.ticket_id) AS total_tickets,
        ROUND(COUNT(t.ticket_id)::numeric / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2) AS tickets_per_customer,
        ROUND(AVG(t.resolution_time)::numeric, 1) AS avg_resolution_hours
    FROM customers c
    LEFT JOIN support_tickets t ON t.customer_id = c.customer_id
    GROUP BY c.customer_segment
)
SELECT
    b.customer_segment,
    b.customers,
    b.avg_mrr,
    b.churn_rate_pct,
    sa.nps_score,
    sa.avg_relationship_csat,
    ta.total_tickets,
    ta.tickets_per_customer,
    ta.avg_resolution_hours
FROM base_agg b
JOIN survey_agg sa USING (customer_segment)
JOIN ticket_agg ta USING (customer_segment)
ORDER BY sa.nps_score DESC;

COMMENT ON VIEW vw_segment_comparison IS 'Side-by-side SMB / Mid-Market / Enterprise comparison across revenue, churn, NPS, CSAT and support load.';
