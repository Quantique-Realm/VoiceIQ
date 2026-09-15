-- Loads data/processed/*.csv into the voiceiq schema. Run from repo root:
--   psql -d voiceiq -f sql/02_load_data.sql

SET search_path TO voiceiq, public;

BEGIN;

TRUNCATE TABLE support_tickets, feedback, surveys, customers RESTART IDENTITY CASCADE;

\copy customers (customer_id, signup_date, country, customer_segment, subscription_plan, monthly_revenue, tenure_months, is_churned, churn_date) FROM 'data/processed/customers.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy surveys (customer_id, survey_date, nps_score, csat_score) FROM 'data/processed/surveys.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy feedback (customer_id, feedback_text, feedback_channel, source_rating, created_at) FROM 'data/processed/feedback.csv' WITH (FORMAT csv, HEADER true, NULL '')

\copy support_tickets (customer_id, category, priority, status, ticket_created_at, ticket_resolved_at, csat_rating) FROM 'data/processed/support_tickets.csv' WITH (FORMAT csv, HEADER true, NULL '')

COMMIT;

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'surveys', COUNT(*) FROM surveys
UNION ALL SELECT 'feedback', COUNT(*) FROM feedback
UNION ALL SELECT 'support_tickets', COUNT(*) FROM support_tickets;
