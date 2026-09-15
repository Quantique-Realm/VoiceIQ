# VoiceIQ — Data Dictionary

Full field-by-field reference for the 4 warehouse tables. `origin` marks
real (from source data), derived (computed from real fields), or modeled
(generated — see `architecture.md` §3 for why and how). The 10 analytics
views are summarized at the end; each view's own SQL is the authoritative
definition (`sql/03_kpis.sql`, `sql/04_customer_experience.sql`).

## customers

| Column | Type | Origin | Description |
|---|---|---|---|
| customer_id | varchar(20) PK | real | Native Telco source key |
| signup_date | date | derived | `reference_date − tenure_months` |
| country | varchar(50) | modeled | Weighted synthetic geographic mix |
| customer_segment | varchar(20) | derived | Revenue tercile: SMB / Mid-Market / Enterprise |
| subscription_plan | varchar(20) | derived | Mapped from real `Contract`: Starter / Growth / Enterprise |
| monthly_revenue | numeric(10,2) | real | From `MonthlyCharges` |
| tenure_months | smallint | real | From `tenure` |
| is_churned | boolean | real | From `Churn` |
| churn_date | date | modeled | Random recent date before snapshot, churned customers only |
| created_at | timestamp | system | Row insert time |

## surveys

| Column | Type | Origin | Description |
|---|---|---|---|
| survey_id | bigserial PK | system | |
| customer_id | varchar(20) FK | — | → customers |
| survey_date | date | modeled | Quarterly wave date |
| nps_score | smallint (0-10) | modeled | Calibrated to SaaS benchmark, correlated with churn/ticket signals |
| csat_score | smallint (1-5) | modeled | Relationship-level, correlated with nps_score |
| nps_category | varchar(10), generated | derived | Promoter/Passive/Detractor, computed in-DB |
| created_at | timestamp | system | |

## feedback

| Column | Type | Origin | Description |
|---|---|---|---|
| feedback_id | bigserial PK | system | |
| customer_id | varchar(20) FK | — | → customers |
| feedback_text | text | real | Play Store review text |
| feedback_channel | varchar(30) | modeled | App Store real; others synthesized |
| source_rating | smallint | — | Always null — source has no star rating |
| sentiment_label | varchar(10) | derived | NLTK VADER, Module 6 |
| sentiment_score | numeric(5,4) | derived | VADER compound score |
| topic_label | varchar(50) | derived | TF-IDF + NMF, Negative feedback only, Module 6 |
| created_at | timestamp | modeled | Sampled across a designed monthly growth curve |

## support_tickets

| Column | Type | Origin | Description |
|---|---|---|---|
| ticket_id | bigserial PK | system | |
| customer_id | varchar(20) FK | — | → customers |
| category | varchar(50) | real | From `Ticket Type` |
| priority | varchar(20) | real | From `Ticket Priority` |
| status | varchar(20) | real | From `Ticket Status` |
| ticket_created_at | timestamp | modeled | Source timestamps unusable (see architecture.md); designed monthly curve |
| ticket_resolved_at | timestamp | modeled | Null unless Closed |
| resolution_time | numeric(10,2), generated | derived | Hours, computed in-DB from the two timestamps |
| csat_rating | smallint (1-5) | real, blended | Real rating nudged by resolution_time vs. SLA deviation |

## Views

| View | Grain | Purpose |
|---|---|---|
| vw_executive_kpis | 1 row | Top-line snapshot: NPS, CSAT, churn, tickets |
| vw_monthly_nps_trend | month | NPS trend, 3mo moving avg, MoM delta |
| vw_csat_by_country | country | Relationship + transactional CSAT, ranked |
| vw_satisfaction_by_plan | plan | NPS/CSAT/churn/MRR by subscription plan |
| vw_segment_comparison | segment | SMB/Mid-Market/Enterprise side by side |
| vw_ticket_resolution_performance | priority | Resolution time, SLA attainment |
| vw_top_complaint_categories | category | Volume + satisfaction ranking |
| vw_repeat_complaints | customer × category | 2+ tickets in same category |
| vw_sentiment_trend | month | Feedback sentiment over time |
| vw_at_risk_customers | customer | Churn-risk tiering, active customers only |
