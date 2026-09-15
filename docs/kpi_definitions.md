# VoiceIQ — KPI Definitions

## NPS (Net Promoter Score)
`% Promoters − % Detractors`, from `surveys.nps_score` (0-10): Promoter ≥9,
Passive 7-8, Detractor ≤6. Range −100 to +100. Industry SaaS benchmark: 30-40.
Source: `vw_monthly_nps_trend`, `vw_executive_kpis.current_nps` (latest
survey per customer).

## Relationship CSAT
Average `surveys.csat_score` (1-5), from the periodic relationship survey.
Distinct from transactional CSAT below. Source: `vw_executive_kpis`,
`vw_csat_by_country`, `vw_satisfaction_by_plan`.

## Transactional CSAT
Average `support_tickets.csat_rating` (1-5), collected per resolved ticket.
Measures satisfaction with a specific support interaction, not the overall
relationship. Source: `vw_executive_kpis.avg_transactional_csat`.

## Churn Rate
`churned_customers / total_customers`, from `customers.is_churned`. A
lagging indicator — see At-Risk Tier below for a leading one.

## Resolution Time
Hours between `ticket_created_at` and `ticket_resolved_at`
(`support_tickets.resolution_time`, generated column). Null while open.

## SLA Attainment
`% of resolved tickets with resolution_time ≤ SLA target`, targets: Critical
8h, High 24h, Medium 48h, Low 96h. Source: `vw_ticket_resolution_performance`.

## Sentiment Score
VADER compound score (−1 to 1) per feedback item; label thresholds ±0.05
(VADER's own convention). Source: `feedback.sentiment_score`,
`vw_sentiment_trend`.

## At-Risk Tier
Composite classification (`vw_at_risk_customers`) from three signals: latest
NPS, NPS trend (vs. previous survey), and recent (90-day) high-severity
ticket exposure. Tiers: Healthy → Watch → Medium Risk → High Risk. Excludes
already-churned customers (a lagging outcome, not a target for retention
action) and never uses the churn flag as an input, to avoid circularity.

## Repeat/Chronic Complaint
A customer with 2 (Repeat) or 3+ (Chronic) tickets in the same category —
a stronger dissatisfaction signal than raw ticket count, since it flags an
unresolved recurring issue. Source: `vw_repeat_complaints`.
