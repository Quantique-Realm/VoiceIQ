-- Support and customer-experience queries
-- Run in psql:  psql -d voiceiq -f sql/04_customer_experience.sql
-- Queries 5 and 6 need notebooks/02_sentiment_analysis.ipynb to have run first.

SET search_path TO voiceiq, public;

-- 1. Resolution time and SLA by priority
-- SLA targets: Critical 8h, High 24h, Medium 48h, Low 96h
SELECT
    priority,
    COUNT(*) AS total_tickets,
    COUNT(resolution_time) AS resolved_tickets,   -- COUNT(column) skips NULLs
    ROUND(AVG(resolution_time), 1) AS avg_resolution_hours,
    ROUND(100.0 * SUM(CASE
                        WHEN priority = 'Critical' AND resolution_time <= 8  THEN 1
                        WHEN priority = 'High'     AND resolution_time <= 24 THEN 1
                        WHEN priority = 'Medium'   AND resolution_time <= 48 THEN 1
                        WHEN priority = 'Low'      AND resolution_time <= 96 THEN 1
                        ELSE 0
                      END) / COUNT(resolution_time), 1) AS within_sla_pct
FROM support_tickets
GROUP BY priority
ORDER BY avg_resolution_hours DESC;

-- 2. Top complaint categories
SELECT
    category,
    COUNT(*) AS tickets,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM support_tickets), 1) AS pct_of_tickets,
    ROUND(AVG(resolution_time), 1) AS avg_resolution_hours,
    ROUND(AVG(csat_rating), 2) AS avg_csat
FROM support_tickets
GROUP BY category
ORDER BY tickets DESC;

-- 3. Does slow resolution lower satisfaction? CSAT by resolution-time bucket
SELECT
    CASE
        WHEN resolution_time < 8  THEN '1: under 8h'
        WHEN resolution_time < 24 THEN '2: 8-24h'
        WHEN resolution_time < 48 THEN '3: 24-48h'
        WHEN resolution_time < 96 THEN '4: 48-96h'
        ELSE '5: over 96h'
    END AS resolution_bucket,
    COUNT(*) AS tickets,
    ROUND(AVG(csat_rating), 2) AS avg_csat
FROM support_tickets
WHERE resolution_time IS NOT NULL
GROUP BY resolution_bucket
ORDER BY resolution_bucket;

-- 4. Customers with repeat complaints (3+ tickets in the same category)
SELECT
    customer_id,
    category,
    COUNT(*) AS tickets
FROM support_tickets
GROUP BY customer_id, category
HAVING COUNT(*) >= 3
ORDER BY tickets DESC;

-- 5. Feedback sentiment by month
SELECT
    DATE_TRUNC('month', created_at)::date AS month,
    COUNT(*) AS feedback_count,
    ROUND(100.0 * SUM(CASE WHEN sentiment_label = 'Negative' THEN 1 ELSE 0 END) / COUNT(*), 1) AS negative_pct,
    ROUND(AVG(sentiment_score), 3) AS avg_sentiment
FROM feedback
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month;

-- 6. Top complaint topics in negative feedback
SELECT
    topic_label,
    COUNT(*) AS feedback_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM feedback WHERE topic_label IS NOT NULL), 1) AS pct
FROM feedback
WHERE topic_label IS NOT NULL
GROUP BY topic_label
ORDER BY feedback_count DESC;

-- 7. At-risk customers (active customers only)
-- High Risk   = unhappy (latest NPS 0-6) AND a Critical/High ticket in the last 90 days
-- Medium Risk = unhappy OR 2+ Critical/High tickets in the last 90 days
-- Watch       = Passive (latest NPS 7-8)
-- The data ends on 2025-06-30, so "last 90 days" counts back from that date.
WITH latest_survey AS (
    SELECT s.customer_id, s.nps_score
    FROM surveys s
    JOIN (SELECT customer_id, MAX(survey_date) AS last_date
          FROM surveys
          GROUP BY customer_id) last
      ON last.customer_id = s.customer_id AND last.last_date = s.survey_date
),
recent_tickets AS (
    SELECT
        customer_id,
        SUM(CASE WHEN priority IN ('Critical', 'High') THEN 1 ELSE 0 END) AS high_severity_tickets
    FROM support_tickets
    WHERE ticket_created_at >= DATE '2025-06-30' - INTERVAL '90 days'
    GROUP BY customer_id
),
customer_risk AS (
    SELECT
        c.customer_id,
        c.customer_segment,
        c.subscription_plan,
        ls.nps_score AS latest_nps,
        COALESCE(rt.high_severity_tickets, 0) AS high_severity_tickets,
        CASE
            WHEN ls.nps_score <= 6 AND COALESCE(rt.high_severity_tickets, 0) >= 1 THEN 'High Risk'
            WHEN ls.nps_score <= 6 OR  COALESCE(rt.high_severity_tickets, 0) >= 2 THEN 'Medium Risk'
            WHEN ls.nps_score <= 8 THEN 'Watch'
            ELSE 'Healthy'
        END AS risk_tier
    FROM customers c
    LEFT JOIN latest_survey ls  ON ls.customer_id = c.customer_id
    LEFT JOIN recent_tickets rt ON rt.customer_id = c.customer_id
    WHERE c.is_churned = FALSE
)
SELECT risk_tier, COUNT(*) AS customers
FROM customer_risk
GROUP BY risk_tier
ORDER BY customers;

-- To get the call list instead of the counts, replace the last SELECT with:
--   SELECT * FROM customer_risk WHERE risk_tier = 'High Risk' ORDER BY latest_nps;
