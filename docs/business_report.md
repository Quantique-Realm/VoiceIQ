# VoiceIQ — Business Report

## Executive summary

NPS has fallen from 37.6 (Q2 2023) to 19.5 (Q2 2025) — a steady two-year
decline, not a blip. Feedback sentiment stayed flat over the same period, so
the decline isn't about how customers talk about the product. The data
points to support experience (serious and slow tickets) and to Starter-plan
customers. 114 active customers are High Risk of churn today; 621 more are
Medium Risk.

## Key findings

**1. NPS is declining while product sentiment is flat.**
NPS by quarter drops from 37.6 to 19.5 (KPI query 3). Average feedback
sentiment holds at about 0.33–0.36 every month (CX query 5).

**2. Support tickets and plan type drive Detractors.**
The logistic regression (notebook 03, AUC 0.71, catches 66% of Detractors)
shows the strongest pushes towards Detractor are: Starter plan, higher
monthly bill, Critical/High tickets in the last 90 days, and slow
resolution. Longer tenure pushes towards Promoter. Starter customers also
churn at 42.7% vs. 2.8% for Enterprise (KPI query 6).

**3. Slow resolution sharply lowers satisfaction.**
Tickets resolved in under 8 hours average 3.18/5 CSAT; tickets taking over
96 hours average 1.44/5 (CX query 3). Correlation: −0.29 (ticket level).

**4. A hidden, cross-segment unhappy group.**
K-Means clustering found ~2,072 customers (29% of the base) with NPS ≈5.9
and CSAT ≈3.2 and the most tickets, spread across Enterprise, Mid-Market,
and SMB. The revenue-based `customer_segment` field cannot see this group.

**5. Bugs are the biggest specific complaint.**
Of 7,505 negative feedback items: 45% general dissatisfaction, 27% bugs &
crashes, 20% ads & pricing, 5% "waste of time", 3% login & account
(CX query 6).

**6. 114 customers are High Risk today.**
CX query 7: 114 High Risk, 621 Medium Risk, 2,077 Watch, 2,362 Healthy
(active customers only). Current state: 26.5% lifetime churn rate, 30.5h
average resolution time, 5,700 open tickets.

## Recommendations

1. **Fix the slow tail of Critical/High tickets.** On average these are
   already inside SLA (4.8h vs. 8h, 14.4h vs. 24h), but ~13% still breach
   it, and 6% of all resolved tickets take over 94 hours. Those are the
   tickets that turn customers into Detractors.
2. **Retention programme for Starter-plan customers** — lowest NPS (23.6)
   and highest churn (42.7%) of any plan; nudging them to annual contracts
   is the obvious lever.
3. **Call the 114 High Risk accounts** — query 7 is a ready-made call list,
   not just a metric.
4. **Add a satisfaction-based segment** next to the revenue tiers, so the
   ~2,072-customer unhappy group shows up in reporting.
5. **Feed bug/crash reports into the roadmap** — the largest specific
   complaint theme.

## Caveats

NPS/CSAT surveys, ticket dates and resolution times are generated (see
`docs/architecture.md` §3), with ticket and churn effects built in. The
findings show the pipeline works end to end; with real survey data the same
SQL and notebooks would measure the real effects.

## Future improvements

- Replace modeled NPS/CSAT with real survey platform data (Qualtrics/Delighted export).
- Add product-usage/login-frequency data to the predictive model.
- Automate the pipeline as a scheduled job once running against live data.
