-- =============================================================================
-- VoiceIQ — Voice of Customer Analytics Platform
-- 01_schema.sql
--
-- Purpose : Normalized warehouse schema for customers, surveys (NPS/CSAT),
--           product/support feedback, and support tickets.
-- Scope   : Dev-runnable DDL (drop-and-recreate) — no migration tool is in
--           the stack (dbt/Flyway are intentionally excluded), so this script
--           is written to be safely re-run against a fresh database.
-- Author  : VoiceIQ Analytics Engineering
-- =============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS voiceiq;
SET search_path TO voiceiq, public;

-- Drop in dependency order (children before parent) so the script is re-runnable.
DROP TABLE IF EXISTS support_tickets CASCADE;
DROP TABLE IF EXISTS feedback        CASCADE;
DROP TABLE IF EXISTS surveys         CASCADE;
DROP TABLE IF EXISTS customers       CASCADE;

-- -----------------------------------------------------------------------------
-- customers — one row per subscriber. Anchors every fact table in the model.
-- Sourced from the Telco Customer Churn dataset; PII (name/email) is dropped
-- at ingestion, so no personal identifiers live in the warehouse.
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id         VARCHAR(20)     PRIMARY KEY,                 -- native source key, e.g. '7590-VHVEG'
    signup_date          DATE            NOT NULL,
    country               VARCHAR(50)     NOT NULL,
    customer_segment     VARCHAR(20)     NOT NULL,
    subscription_plan   VARCHAR(20)     NOT NULL,
    monthly_revenue      NUMERIC(10,2)   NOT NULL DEFAULT 0,          -- MRR contribution, from source MonthlyCharges
    tenure_months          SMALLINT        NOT NULL,
    is_churned             BOOLEAN         NOT NULL DEFAULT FALSE,      -- ground-truth churn label; used to validate at-risk heuristics, not as a modeling input
    churn_date             DATE,
    created_at              TIMESTAMP       NOT NULL DEFAULT now(),

    CONSTRAINT chk_cust_segment    CHECK (customer_segment IN ('SMB', 'Mid-Market', 'Enterprise')),
    CONSTRAINT chk_cust_plan       CHECK (subscription_plan IN ('Starter', 'Growth', 'Enterprise')),
    CONSTRAINT chk_cust_revenue    CHECK (monthly_revenue >= 0),
    CONSTRAINT chk_cust_tenure     CHECK (tenure_months >= 0),
    CONSTRAINT chk_cust_churn_date CHECK (churn_date IS NULL OR churn_date >= signup_date),
    CONSTRAINT chk_cust_churn_flag CHECK ((is_churned AND churn_date IS NOT NULL) OR (NOT is_churned AND churn_date IS NULL))
);

COMMENT ON TABLE  customers IS 'Customer dimension: one row per subscriber, anchors surveys/feedback/support_tickets.';
COMMENT ON COLUMN customers.monthly_revenue IS 'Monthly recurring revenue for this customer, in USD.';
COMMENT ON COLUMN customers.is_churned      IS 'Ground-truth churn flag from source data; used only to validate at-risk scoring, never as a leaked feature in it.';

-- -----------------------------------------------------------------------------
-- surveys — periodic relationship survey: NPS + relationship CSAT.
-- Distinct from support_tickets.csat_rating, which is a transactional,
-- post-interaction CSAT tied to a single ticket. Real VoC programs
-- (Qualtrics, Delighted) separate these two instruments; this schema mirrors
-- that distinction rather than conflating them into one score.
-- -----------------------------------------------------------------------------
CREATE TABLE surveys (
    survey_id     BIGSERIAL       PRIMARY KEY,
    customer_id  VARCHAR(20)     NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    survey_date  DATE            NOT NULL,
    nps_score    SMALLINT        NOT NULL,                            -- 0-10, "how likely to recommend"
    csat_score  SMALLINT,                                            -- 1-5, relationship-level satisfaction; nullable (not every survey asks both questions)
    nps_category VARCHAR(10)     GENERATED ALWAYS AS (
                                     CASE
                                         WHEN nps_score >= 9 THEN 'Promoter'
                                         WHEN nps_score >= 7 THEN 'Passive'
                                         ELSE 'Detractor'
                                     END
                                 ) STORED,
    created_at    TIMESTAMP       NOT NULL DEFAULT now(),

    CONSTRAINT chk_survey_nps  CHECK (nps_score BETWEEN 0 AND 10),
    CONSTRAINT chk_survey_csat CHECK (csat_score IS NULL OR csat_score BETWEEN 1 AND 5)
);

COMMENT ON TABLE  surveys IS 'Periodic relationship survey responses: NPS (0-10) and relationship CSAT (1-5) per customer.';
COMMENT ON COLUMN surveys.nps_category IS 'Derived, stored classification of nps_score (Promoter/Passive/Detractor) — computed once here so every downstream query/report agrees.';

-- -----------------------------------------------------------------------------
-- feedback — free-text Voice-of-Customer input from any channel.
-- sentiment_label/sentiment_score are populated by the NLP pipeline
-- (notebooks/02_sentiment_analysis.ipynb, Module 6) — nullable here because
-- scoring happens after load, not at ingestion.
-- -----------------------------------------------------------------------------
CREATE TABLE feedback (
    feedback_id       BIGSERIAL       PRIMARY KEY,
    customer_id      VARCHAR(20)     NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    feedback_text    TEXT            NOT NULL,
    feedback_channel VARCHAR(30)     NOT NULL,
    source_rating     SMALLINT,                                        -- 1-5 star rating, where the channel provides one (e.g. app store reviews)
    sentiment_label   VARCHAR(10),                                     -- filled by Module 6: Positive / Neutral / Negative
    sentiment_score   NUMERIC(5,4),                                    -- filled by Module 6: compound polarity, -1..1
    topic_label       VARCHAR(50),                                     -- filled by Module 6: NMF-derived complaint topic, Negative feedback only
    created_at         TIMESTAMP       NOT NULL,

    CONSTRAINT chk_feedback_text     CHECK (length(btrim(feedback_text)) > 0),
    CONSTRAINT chk_feedback_channel  CHECK (feedback_channel IN ('App Store', 'In-App Survey', 'Support Chat', 'Email')),
    CONSTRAINT chk_feedback_rating   CHECK (source_rating IS NULL OR source_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_feedback_sentiment_label CHECK (sentiment_label IS NULL OR sentiment_label IN ('Positive', 'Neutral', 'Negative')),
    CONSTRAINT chk_feedback_sentiment_score CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN -1 AND 1)
);

COMMENT ON TABLE  feedback IS 'Free-text customer feedback from any channel, with NLP-derived sentiment attached post-load.';
COMMENT ON COLUMN feedback.topic_label IS 'Business-labeled NMF topic (TF-IDF) for Negative-sentiment feedback — see notebooks/02_sentiment_analysis.ipynb. Null for Positive/Neutral rows and before Module 6 runs.';

-- -----------------------------------------------------------------------------
-- support_tickets — one row per support interaction.
-- resolution_time is a generated column so it can never drift from the raw
-- created/resolved timestamps it is computed from.
-- -----------------------------------------------------------------------------
CREATE TABLE support_tickets (
    ticket_id            BIGSERIAL       PRIMARY KEY,
    customer_id         VARCHAR(20)     NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    category              VARCHAR(50)     NOT NULL,
    priority               VARCHAR(20)     NOT NULL,
    status                 VARCHAR(20)     NOT NULL,
    ticket_created_at   TIMESTAMP       NOT NULL,
    ticket_resolved_at TIMESTAMP,                                    -- NULL while the ticket is still open
    resolution_time       NUMERIC(10,2)   GENERATED ALWAYS AS (
                                             EXTRACT(EPOCH FROM (ticket_resolved_at - ticket_created_at)) / 3600.0
                                         ) STORED,                    -- hours; NULL until resolved
    csat_rating            SMALLINT,                                   -- transactional, per-ticket CSAT (1-5) — the one genuinely real score in the model

    CONSTRAINT chk_ticket_priority   CHECK (priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT chk_ticket_status     CHECK (status IN ('Open', 'In Progress', 'Resolved', 'Closed')),
    CONSTRAINT chk_ticket_csat       CHECK (csat_rating IS NULL OR csat_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_ticket_dates      CHECK (ticket_resolved_at IS NULL OR ticket_resolved_at >= ticket_created_at),
    CONSTRAINT chk_ticket_resolution CHECK (
        (status IN ('Resolved', 'Closed') AND ticket_resolved_at IS NOT NULL) OR
        (status IN ('Open', 'In Progress') AND ticket_resolved_at IS NULL)
    )
);

COMMENT ON TABLE  support_tickets IS 'One row per support interaction; resolution_time (hours) is derived, never stored independently of its source timestamps.';
COMMENT ON COLUMN support_tickets.csat_rating IS 'Source-provided transactional CSAT for this ticket, blended with resolution_time deviation from SLA (see docs/architecture.md §3) — distinct from surveys.csat_score (relationship-level).';

-- -----------------------------------------------------------------------------
-- Indexes — every FK, plus the columns the analytics layer (sql/03, sql/04)
-- filters, groups, or trends by.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_customers_segment      ON customers(customer_segment);
CREATE INDEX idx_customers_country      ON customers(country);
CREATE INDEX idx_customers_plan         ON customers(subscription_plan);

CREATE INDEX idx_surveys_customer_id    ON surveys(customer_id);
CREATE INDEX idx_surveys_survey_date    ON surveys(survey_date);

CREATE INDEX idx_feedback_customer_id   ON feedback(customer_id);
CREATE INDEX idx_feedback_created_at    ON feedback(created_at);
CREATE INDEX idx_feedback_channel       ON feedback(feedback_channel);
-- Partial: topic_label is only populated for Negative feedback (Module 6), so most rows are NULL.
CREATE INDEX idx_feedback_topic         ON feedback(topic_label) WHERE topic_label IS NOT NULL;

CREATE INDEX idx_tickets_customer_id    ON support_tickets(customer_id);
CREATE INDEX idx_tickets_created_at     ON support_tickets(ticket_created_at);
CREATE INDEX idx_tickets_category       ON support_tickets(category);
CREATE INDEX idx_tickets_priority       ON support_tickets(priority);
-- Partial index: the "open tickets" KPI on the Executive Overview page hits this filter constantly.
CREATE INDEX idx_tickets_open           ON support_tickets(status) WHERE status IN ('Open', 'In Progress');

COMMIT;
