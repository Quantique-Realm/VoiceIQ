# VoiceIQ — KPI Definitions

Query numbers refer to `sql/03_kpis.sql` (KPI) and `sql/04_customer_experience.sql` (CX).

## NPS (Net Promoter Score)
`% Promoters − % Detractors`, from `surveys.nps_score` (0-10): Promoter ≥9,
Passive 7-8, Detractor ≤6. Range −100 to +100. Industry SaaS benchmark: 30-40.
Source: KPI queries 2-5.

## Relationship CSAT
Average `surveys.csat_score` (1-5), from the periodic relationship survey.
Distinct from transactional CSAT below. Source: KPI queries 2-4.

## Transactional CSAT
Average `support_tickets.csat_rating` (1-5), collected per resolved ticket.
Measures satisfaction with a specific support interaction, not the overall
relationship. Source: KPI query 7, CX queries 2-3.

## Churn Rate
`churned_customers / total_customers`, from `customers.is_churned`. A
lagging indicator — see At-Risk Tier below for a leading one. Source: KPI
queries 1 and 6.

## Resolution Time
Hours between `ticket_created_at` and `ticket_resolved_at`
(`support_tickets.resolution_time`, generated column). Null while open.

## SLA Attainment
`% of resolved tickets with resolution_time ≤ SLA target`, targets: Critical
8h, High 24h, Medium 48h, Low 96h. Source: CX query 1.

## Sentiment Score
VADER compound score (−1 to 1) per feedback item; ≥ 0.05 Positive, ≤ −0.05
Negative (VADER's own convention). Source: `feedback.sentiment_score`, CX query 5.

## At-Risk Tier
Classification of active customers (CX query 7) from two signals: latest NPS
and Critical/High tickets in the last 90 days of the data. High Risk = NPS
0-6 and 1+ serious ticket; Medium Risk = NPS 0-6 or 2+ serious tickets;
Watch = NPS 7-8; otherwise Healthy. Churned customers are excluded (they
are already gone), and the churn flag is never an input.

## Repeat Complaint
A customer with 3+ tickets in the same category — a stronger dissatisfaction
signal than raw ticket count, since it flags an unresolved recurring issue.
Source: CX query 4.
