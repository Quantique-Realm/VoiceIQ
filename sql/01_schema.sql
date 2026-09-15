-- VoiceIQ warehouse schema

BEGIN;

CREATE SCHEMA IF NOT EXISTS voiceiq;
SET search_path TO voiceiq, public;

DROP TABLE IF EXISTS support_tickets CASCADE;
DROP TABLE IF EXISTS feedback        CASCADE;
DROP TABLE IF EXISTS surveys         CASCADE;
DROP TABLE IF EXISTS customers       CASCADE;

CREATE TABLE customers (
    customer_id       VARCHAR(20)   PRIMARY KEY,
    signup_date       DATE          NOT NULL,
    country           VARCHAR(50)   NOT NULL,
    customer_segment  VARCHAR(20)   NOT NULL,
    subscription_plan VARCHAR(20)   NOT NULL,
    monthly_revenue   NUMERIC(10,2) NOT NULL DEFAULT 0,
    tenure_months     SMALLINT      NOT NULL,
    is_churned        BOOLEAN       NOT NULL DEFAULT FALSE,
    churn_date        DATE,
    created_at        TIMESTAMP     NOT NULL DEFAULT now(),

    CONSTRAINT chk_cust_segment    CHECK (customer_segment IN ('SMB', 'Mid-Market', 'Enterprise')),
    CONSTRAINT chk_cust_plan       CHECK (subscription_plan IN ('Starter', 'Growth', 'Enterprise')),
    CONSTRAINT chk_cust_revenue    CHECK (monthly_revenue >= 0),
    CONSTRAINT chk_cust_tenure     CHECK (tenure_months >= 0),
    CONSTRAINT chk_cust_churn_date CHECK (churn_date IS NULL OR churn_date >= signup_date),
    CONSTRAINT chk_cust_churn_flag CHECK ((is_churned AND churn_date IS NOT NULL) OR (NOT is_churned AND churn_date IS NULL))
);

CREATE TABLE surveys (
    survey_id    BIGSERIAL   PRIMARY KEY,
    customer_id  VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    survey_date  DATE        NOT NULL,
    nps_score    SMALLINT    NOT NULL,
    csat_score   SMALLINT,
    nps_category VARCHAR(10) GENERATED ALWAYS AS (
        CASE WHEN nps_score >= 9 THEN 'Promoter'
             WHEN nps_score >= 7 THEN 'Passive'
             ELSE 'Detractor' END
    ) STORED,
    created_at   TIMESTAMP   NOT NULL DEFAULT now(),

    CONSTRAINT chk_survey_nps  CHECK (nps_score BETWEEN 0 AND 10),
    CONSTRAINT chk_survey_csat CHECK (csat_score IS NULL OR csat_score BETWEEN 1 AND 5)
);

-- sentiment_label/score/topic_label are filled post-load by notebooks/02_sentiment_analysis.ipynb
CREATE TABLE feedback (
    feedback_id      BIGSERIAL   PRIMARY KEY,
    customer_id      VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    feedback_text    TEXT        NOT NULL,
    feedback_channel VARCHAR(30) NOT NULL,
    source_rating    SMALLINT,
    sentiment_label  VARCHAR(10),
    sentiment_score  NUMERIC(5,4),
    topic_label      VARCHAR(50),
    created_at       TIMESTAMP   NOT NULL,

    CONSTRAINT chk_feedback_text     CHECK (length(btrim(feedback_text)) > 0),
    CONSTRAINT chk_feedback_channel  CHECK (feedback_channel IN ('App Store', 'In-App Survey', 'Support Chat', 'Email')),
    CONSTRAINT chk_feedback_rating   CHECK (source_rating IS NULL OR source_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_feedback_sentiment_label CHECK (sentiment_label IS NULL OR sentiment_label IN ('Positive', 'Neutral', 'Negative')),
    CONSTRAINT chk_feedback_sentiment_score CHECK (sentiment_score IS NULL OR sentiment_score BETWEEN -1 AND 1)
);

-- resolution_time is derived so it can't drift from its source timestamps
CREATE TABLE support_tickets (
    ticket_id          BIGSERIAL   PRIMARY KEY,
    customer_id        VARCHAR(20) NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    category           VARCHAR(50) NOT NULL,
    priority           VARCHAR(20) NOT NULL,
    status             VARCHAR(20) NOT NULL,
    ticket_created_at  TIMESTAMP   NOT NULL,
    ticket_resolved_at TIMESTAMP,
    resolution_time    NUMERIC(10,2) GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (ticket_resolved_at - ticket_created_at)) / 3600.0
    ) STORED,
    csat_rating        SMALLINT,

    CONSTRAINT chk_ticket_priority   CHECK (priority IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT chk_ticket_status     CHECK (status IN ('Open', 'In Progress', 'Resolved', 'Closed')),
    CONSTRAINT chk_ticket_csat       CHECK (csat_rating IS NULL OR csat_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_ticket_dates      CHECK (ticket_resolved_at IS NULL OR ticket_resolved_at >= ticket_created_at),
    CONSTRAINT chk_ticket_resolution CHECK (
        (status IN ('Resolved', 'Closed') AND ticket_resolved_at IS NOT NULL) OR
        (status IN ('Open', 'In Progress') AND ticket_resolved_at IS NULL)
    )
);

CREATE INDEX idx_customers_segment ON customers(customer_segment);
CREATE INDEX idx_customers_country ON customers(country);
CREATE INDEX idx_customers_plan    ON customers(subscription_plan);

CREATE INDEX idx_surveys_customer_id ON surveys(customer_id);
CREATE INDEX idx_surveys_survey_date ON surveys(survey_date);

CREATE INDEX idx_feedback_customer_id ON feedback(customer_id);
CREATE INDEX idx_feedback_created_at  ON feedback(created_at);
CREATE INDEX idx_feedback_channel     ON feedback(feedback_channel);
CREATE INDEX idx_feedback_topic       ON feedback(topic_label) WHERE topic_label IS NOT NULL;

CREATE INDEX idx_tickets_customer_id ON support_tickets(customer_id);
CREATE INDEX idx_tickets_created_at  ON support_tickets(ticket_created_at);
CREATE INDEX idx_tickets_category    ON support_tickets(category);
CREATE INDEX idx_tickets_priority    ON support_tickets(priority);
CREATE INDEX idx_tickets_open        ON support_tickets(status) WHERE status IN ('Open', 'In Progress');

COMMIT;
