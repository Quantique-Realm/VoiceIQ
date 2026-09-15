-- =============================================================================
-- VoiceIQ — Voice of Customer Analytics Platform
-- 04_customer_experience.sql
--
-- Purpose : Support-operations and customer-experience deep-dive views for
--           the Power BI "Support Analytics" and "Customer Experience" pages.
-- Usage   : psql -d voiceiq -f sql/04_customer_experience.sql
--
-- Note on vw_sentiment_trend: feedback.sentiment_label / sentiment_score are
-- populated by the NLP pipeline in Module 6 (notebooks/02_sentiment_analysis.ipynb).
-- The view is defined now, against the schema that already supports it, and
-- will return real trend data once that notebook has run — today it runs
-- cleanly but every sentiment aggregate is NULL, which is expected.
-- =============================================================================

SET search_path TO voiceiq, public;

-- -----------------------------------------------------------------------------
-- 6. TICKET RESOLUTION PERFORMANCE
-- Median via PERCENTILE_CONT (mean alone hides a long tail of slow tickets),
-- SLA attainment %, and a RANK of the slowest priority tier.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ticket_resolution_performance AS
WITH sla_targets (priority, sla_hours) AS (
    VALUES ('Critical', 8.0), ('High', 24.0), ('Medium', 48.0), ('Low', 96.0)
)
SELECT
    t.priority,
    st.sla_hours,
    COUNT(*) AS total_tickets,
    COUNT(*) FILTER (WHERE t.resolution_time IS NOT NULL) AS resolved_tickets,
    ROUND(AVG(t.resolution_time)::numeric, 1) AS avg_resolution_hours,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t.resolution_time)::numeric, 1) AS median_resolution_hours,
    ROUND(100.0 * COUNT(*) FILTER (WHERE t.resolution_time <= st.sla_hours)
                / NULLIF(COUNT(*) FILTER (WHERE t.resolution_time IS NOT NULL), 0), 1) AS sla_attainment_pct,
    RANK() OVER (ORDER BY AVG(t.resolution_time) DESC) AS slowest_priority_rank
FROM support_tickets t
JOIN sla_targets st ON st.priority = t.priority
GROUP BY t.priority, st.sla_hours
ORDER BY avg_resolution_hours DESC;

COMMENT ON VIEW vw_ticket_resolution_performance IS 'Resolution-time performance and SLA attainment by ticket priority.';

-- -----------------------------------------------------------------------------
-- 7. TOP COMPLAINT CATEGORIES
-- SUM() OVER () for share-of-total, two independent RANK()s (highest volume,
-- worst satisfaction) so both cuts are available to the dashboard in one view.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_top_complaint_categories AS
WITH category_stats AS (
    SELECT
        category,
        COUNT(*) AS ticket_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all_tickets,
        ROUND(AVG(resolution_time)::numeric, 1) AS avg_resolution_hours,
        ROUND(AVG(csat_rating)::numeric, 2) AS avg_csat_rating,
        COUNT(*) FILTER (WHERE priority IN ('Critical', 'High')) AS high_severity_count
    FROM support_tickets
    GROUP BY category
)
SELECT
    category,
    ticket_count,
    pct_of_all_tickets,
    avg_resolution_hours,
    avg_csat_rating,
    high_severity_count,
    RANK() OVER (ORDER BY ticket_count DESC)      AS volume_rank,
    RANK() OVER (ORDER BY avg_csat_rating ASC)    AS worst_csat_rank
FROM category_stats
ORDER BY ticket_count DESC;

COMMENT ON VIEW vw_top_complaint_categories IS 'Ticket categories ranked by volume and by satisfaction, with share-of-total.';

-- -----------------------------------------------------------------------------
-- 8. REPEAT COMPLAINT ANALYSIS
-- Customers who filed 2+ tickets in the SAME category — a stronger churn
-- signal than raw ticket volume, since it flags an unresolved recurring
-- problem rather than several one-off issues.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_repeat_complaints AS
WITH ticket_sequence AS (
    SELECT
        customer_id,
        category,
        ticket_created_at,
        COUNT(*) OVER (PARTITION BY customer_id, category) AS tickets_in_category
    FROM support_tickets
)
SELECT
    customer_id,
    category,
    tickets_in_category,
    MIN(ticket_created_at) AS first_ticket_date,
    MAX(ticket_created_at) AS latest_ticket_date,
    CASE
        WHEN tickets_in_category >= 3 THEN 'Chronic'
        WHEN tickets_in_category = 2 THEN 'Repeat'
        ELSE 'One-time'
    END AS complaint_pattern
FROM ticket_sequence
GROUP BY customer_id, category, tickets_in_category
HAVING tickets_in_category >= 2
ORDER BY tickets_in_category DESC, latest_ticket_date DESC;

COMMENT ON VIEW vw_repeat_complaints IS 'Customers with 2+ tickets in the same category — recurring, unresolved problems.';

-- -----------------------------------------------------------------------------
-- 9. SENTIMENT TREND OVER TIME
-- Populated once Module 6's NLP pipeline writes sentiment_label/sentiment_score.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_sentiment_trend AS
WITH monthly_sentiment AS (
    SELECT
        DATE_TRUNC('month', created_at)::date AS feedback_month,
        COUNT(*) AS feedback_count,
        COUNT(*) FILTER (WHERE sentiment_label = 'Positive') AS positive_count,
        COUNT(*) FILTER (WHERE sentiment_label = 'Negative') AS negative_count,
        ROUND(AVG(sentiment_score)::numeric, 3) AS avg_sentiment_score
    FROM feedback
    GROUP BY 1
)
SELECT
    feedback_month,
    feedback_count,
    positive_count,
    negative_count,
    avg_sentiment_score,
    ROUND(AVG(avg_sentiment_score) OVER (
        ORDER BY feedback_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 3) AS sentiment_3mo_moving_avg,
    avg_sentiment_score - LAG(avg_sentiment_score) OVER (ORDER BY feedback_month) AS sentiment_mom_change
FROM monthly_sentiment
ORDER BY feedback_month;

COMMENT ON VIEW vw_sentiment_trend IS 'Monthly feedback sentiment with 3-month moving average. Populated after Module 6 (NLP pipeline) runs.';

-- -----------------------------------------------------------------------------
-- 10. AT-RISK CUSTOMER IDENTIFICATION
-- Composite risk tiering from three independent signals: a declining NPS
-- trend (LAG between a customer's two most recent surveys), recent
-- high-severity support load, and low current NPS. Ground-truth is_churned
-- is used only to exclude already-churned customers from a "who to save"
-- list — never as an input to the risk tier itself (would be circular).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_at_risk_customers AS
WITH survey_trend AS (
    SELECT
        customer_id,
        nps_score,
        LAG(nps_score) OVER (PARTITION BY customer_id ORDER BY survey_date) AS prev_nps_score,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY survey_date DESC) AS rn
    FROM surveys
),
latest_survey AS (
    SELECT
        customer_id,
        nps_score AS latest_nps,
        nps_score - COALESCE(prev_nps_score, nps_score) AS nps_delta
    FROM survey_trend
    WHERE rn = 1
),
recent_tickets AS (
    SELECT
        customer_id,
        COUNT(*) AS tickets_last_90d,
        COUNT(*) FILTER (WHERE priority IN ('Critical', 'High')) AS high_severity_last_90d,
        ROUND(AVG(csat_rating)::numeric, 2) AS avg_recent_csat
    FROM support_tickets
    WHERE ticket_created_at >= (SELECT MAX(ticket_created_at) FROM support_tickets) - INTERVAL '90 days'
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_segment,
    c.subscription_plan,
    c.tenure_months,
    ls.latest_nps,
    ls.nps_delta,
    COALESCE(rt.tickets_last_90d, 0) AS tickets_last_90d,
    COALESCE(rt.high_severity_last_90d, 0) AS high_severity_last_90d,
    rt.avg_recent_csat,
    CASE
        WHEN ls.latest_nps <= 6 AND COALESCE(rt.high_severity_last_90d, 0) >= 1 THEN 'High Risk'
        WHEN ls.latest_nps <= 6 OR ls.nps_delta <= -3 OR COALESCE(rt.high_severity_last_90d, 0) >= 2 THEN 'Medium Risk'
        WHEN ls.latest_nps <= 8 THEN 'Watch'
        ELSE 'Healthy'
    END AS risk_tier
FROM customers c
LEFT JOIN latest_survey ls ON ls.customer_id = c.customer_id
LEFT JOIN recent_tickets rt ON rt.customer_id = c.customer_id
WHERE NOT c.is_churned   -- already-churned customers are a lagging indicator, not a retention target
ORDER BY
    CASE
        WHEN ls.latest_nps <= 6 AND COALESCE(rt.high_severity_last_90d, 0) >= 1 THEN 1
        WHEN ls.latest_nps <= 6 OR ls.nps_delta <= -3 OR COALESCE(rt.high_severity_last_90d, 0) >= 2 THEN 2
        WHEN ls.latest_nps <= 8 THEN 3
        ELSE 4
    END,
    ls.latest_nps ASC NULLS LAST;

COMMENT ON VIEW vw_at_risk_customers IS 'Active customers tiered by churn risk from NPS trend + recent support severity — for the retention-priority list.';
