# VoiceIQ — Business Report

## Executive summary

NPS has declined from 39 (Apr 2023) to 19 (Jun 2025) — a two-year erosion,
not a blip. The data points to a specific, fixable cause: slow, high-severity
support resolution, not product-wide dissatisfaction. 104 active customers
are currently High Risk of churn; 793 more are Medium Risk. Fixing support
triage is the highest-leverage lever available.

## Key findings

**1. NPS is declining, driven by support experience, not broad dissatisfaction.**
The logistic regression (Module 7) shows a Critical/High-severity ticket in
the trailing 90 days is the single strongest driver of becoming a Detractor
(odds ratio 0.64) — stronger than plan, segment, or revenue.

**2. Resolution speed and satisfaction move together, sharply.**
Tickets resolved in under 8 hours average 3.14/5 CSAT; tickets taking over
96 hours average 1.33/5 — a drop of more than 2 points. Correlation:
r ≈ −0.29 (ticket-level).

**3. A hidden, cross-segment dissatisfaction cluster.**
Unsupervised clustering found ~1,909 customers (27% of the base) with NPS
≈5.8 and CSAT ≈3.0 — spanning Enterprise, Mid-Market, and SMB almost evenly.
The current revenue-based `customer_segment` field cannot see this group.

**4. Most negative feedback is generic reliability complaints, not features.**
Of 7,505 negative feedback items: 59.6% are bugs/errors ("app not working"),
22.4% ads/monetization frustration, 9.8% general dissatisfaction, 8.2%
perceived waste of time. Reliability, not any single feature, is the top
driver of negative feedback.

**5. 104 customers are High Risk today.**
`vw_at_risk_customers`: 104 High Risk, 793 Medium Risk, 1,879 Watch, 2,398
Healthy (active customers only). Current state: 26.5% lifetime churn rate,
30.8h average resolution time, 5,700 open tickets.

## Recommendations

1. **Prioritize Critical/High ticket triage** — the single largest lever on
   NPS found in the data. Target: cut average resolution time on these two
   tiers first (currently 4.9h / 14.6h vs. 8h / 24h SLA — already inside SLA
   on average, so the fix is the *tail*, not the average: investigate the
   ~7% of tickets that breach SLA badly, not the median).
2. **Build a satisfaction-based segment** alongside the revenue tiers to
   surface the ~1,909-customer dissatisfaction cluster for targeted outreach
   — it is invisible to any dashboard cut by `customer_segment` alone.
3. **Action the 104 High Risk accounts directly** via `vw_at_risk_customers`
   — this is a ready-to-use retention call list, not just a metric.
4. **Investigate reliability/bug reports as a roadmap input** — 60% of
   negative feedback traces to "it doesn't work," ahead of any specific
   feature request.

## Future improvements

- Replace modeled NPS/CSAT with real survey platform data (Qualtrics/Delighted export) if this becomes a live system.
- Extend the predictive model with real product-usage/login-frequency data — not available in the current public datasets, likely to raise the model's AUC beyond 0.63.
- Automate the pipeline (Modules 3-6) as a scheduled job once running against live data.
