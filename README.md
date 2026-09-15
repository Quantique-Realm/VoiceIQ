# VoiceIQ — Voice of Customer Analytics Platform

A Qualtrics-inspired Customer Experience & Feedback Intelligence platform for a
B2B SaaS company: NPS/CSAT surveys, support tickets, and product feedback
consolidated into a PostgreSQL warehouse, analyzed with SQL + Python, and
surfaced through a Power BI executive dashboard.

**Status: in progress (Modules 1-6 of 10 complete).** Full README, business
report, and dashboard land in later modules — until then, start with
[`docs/architecture.md`](docs/architecture.md) for the dataset selection,
data lineage, and pipeline architecture.

## What's built so far

| Module | Deliverable |
|---|---|
| 1. Dataset selection & architecture | [`docs/architecture.md`](docs/architecture.md) |
| 2. PostgreSQL schema | [`sql/01_schema.sql`](sql/01_schema.sql) |
| 3. Data loading | [`notebooks/01_data_cleaning.ipynb`](notebooks/01_data_cleaning.ipynb), [`sql/02_load_data.sql`](sql/02_load_data.sql) |
| 4. SQL analytics | [`sql/03_kpis.sql`](sql/03_kpis.sql), [`sql/04_customer_experience.sql`](sql/04_customer_experience.sql) |
| 5. Python EDA | [`notebooks/03_customer_insights.ipynb`](notebooks/03_customer_insights.ipynb) |
| 6. Sentiment analysis | [`notebooks/02_sentiment_analysis.ipynb`](notebooks/02_sentiment_analysis.ipynb) |

## Tech stack

PostgreSQL · SQL · Python (Pandas, NumPy, Scikit-learn, NLTK) · Power BI

## Local setup

Raw datasets aren't committed (size + licensing) — see `docs/architecture.md`
§2 for the three public Kaggle sources and where to place them under
`data/raw/`. A Python virtual environment (`.venv/`) and PostgreSQL 14+ are
required to reproduce the pipeline end to end.
