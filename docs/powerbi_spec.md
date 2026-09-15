# VoiceIQ — Power BI Build Spec

Power BI Desktop is Windows-only, so the `.pbix` itself isn't built in this
repo. This spec is complete enough to build it directly: data model, DAX
measures, and page-by-page visuals. A working HTML replica of the same
4 pages, built from live data, stands in for now — see the main README.

## Data source

Connect via the Postgres connector to the `voiceiq` schema. Import the 4
base tables (`customers`, `surveys`, `feedback`, `support_tickets`) rather
than the `sql/03_kpis.sql` / `04_customer_experience.sql` views — importing
base tables lets every visual stay slicer-interactive (filter by segment,
country, date range); the views bake in one fixed aggregation grain.

## Model relationships

`customers[customer_id]` (1) → `surveys[customer_id]` (*)
`customers[customer_id]` (1) → `feedback[customer_id]` (*)
`customers[customer_id]` (1) → `support_tickets[customer_id]` (*)

## DAX measures

```
Total Customers      = DISTINCTCOUNT(customers[customer_id])
Churned Customers    = CALCULATE([Total Customers], customers[is_churned] = TRUE)
Churn Rate %         = DIVIDE([Churned Customers], [Total Customers])

NPS                  = DIVIDE(
                          CALCULATE(COUNTROWS(surveys), surveys[nps_category] = "Promoter")
                          - CALCULATE(COUNTROWS(surveys), surveys[nps_category] = "Detractor"),
                          COUNTROWS(surveys)
                        ) * 100
Avg Relationship CSAT = AVERAGE(surveys[csat_score])
Avg Transactional CSAT = AVERAGE(support_tickets[csat_rating])

Open Tickets         = CALCULATE(COUNTROWS(support_tickets), support_tickets[status] IN {"Open","In Progress"})
Resolved Tickets     = CALCULATE(COUNTROWS(support_tickets), support_tickets[status] IN {"Resolved","Closed"})
Avg Resolution Hours = AVERAGE(support_tickets[resolution_time])
SLA Target Hours     = SWITCH(SELECTEDVALUE(support_tickets[priority]), "Critical", 8, "High", 24, "Medium", 48, "Low", 96)
SLA Attainment %     = DIVIDE(
                          CALCULATE(COUNTROWS(support_tickets), support_tickets[resolution_time] <= [SLA Target Hours]),
                          [Resolved Tickets]
                        )

Positive Feedback %  = DIVIDE(CALCULATE(COUNTROWS(feedback), feedback[sentiment_label]="Positive"), COUNTROWS(feedback))
Negative Feedback %  = DIVIDE(CALCULATE(COUNTROWS(feedback), feedback[sentiment_label]="Negative"), COUNTROWS(feedback))
Avg Sentiment Score  = AVERAGE(feedback[sentiment_score])
```

Add a Date table (`CALENDAR`) keyed off `survey_date` / `ticket_created_at` /
`feedback.created_at` via separate relationships if cross-page date slicing
is needed; each fact table has its own event date, so a single shared date
dimension needs one active + role-playing relationships (mark one active per
table, use `USERELATIONSHIP` in date-scoped measures).

## Page 1 — Executive Overview

- KPI cards: NPS, Avg Relationship CSAT, Total Customers, Open Tickets
- Line chart: NPS by month (`surveys[survey_date]` monthly, `[NPS]` measure)
- Card: Churn Rate %

## Page 2 — Customer Feedback

- Donut/bar: sentiment breakdown (`feedback[sentiment_label]`)
- Word cloud visual (Power BI native/marketplace): `feedback[feedback_text]`, filtered to Negative
- Bar: top complaint topics (`feedback[topic_label]`, count)
- Bar: feedback volume by channel (`feedback[feedback_channel]`)

## Page 3 — Support Analytics

- Bar: Avg Resolution Hours by `support_tickets[priority]`
- Donut: ticket count by `support_tickets[priority]`
- Table: `support_tickets[category]` × ticket count, avg resolution, avg CSAT
- Gauge/bar: SLA Attainment % by priority

## Page 4 — Customer Experience

- Bar: NPS by `customers[customer_segment]`
- Bar/map: Avg Relationship CSAT by `customers[country]`
- Table: at-risk customers — reproduce `vw_at_risk_customers`' logic as
  calculated columns/measures (latest NPS via `LASTNONBLANK`, recent
  high-severity ticket count via `CALCULATE` with a 90-day date filter)
- Line: monthly sentiment trend (`feedback[created_at]` monthly, `[Avg Sentiment Score]`)

## Theme

Executive blue and white — primary `#2A78D6`, neutrals `#FCFCFB` / `#0B0B0B`,
status colors good `#0CA30C` / warning `#FAB219` / critical `#D03B3B` (same
palette used across the notebooks and the HTML dashboard, for one consistent
visual identity across the whole project).
