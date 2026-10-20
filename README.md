# VoiceIQ — Customer Feedback Analytics

A customer experience analytics project for a subscription software company.
It combines surveys, support tickets and customer reviews in a PostgreSQL
database, then analyses them with SQL and Python.

## Questions it answers

- Why are customers unhappy?
- Which problems cause the most complaints?
- What turns a customer into a Promoter or a Detractor?
- Which customers are likely to leave?
- Is customer sentiment getting better or worse?

## Data

Three public Kaggle datasets:

| Dataset | Used for |
|---|---|
| [Telco Customer Churn](https://www.kaggle.com/datasets/blastchar/telco-customer-churn) | Customers (tenure, monthly bill, churn) |
| [Customer Support Tickets](https://www.kaggle.com/datasets/suraj520/customer-support-ticket-dataset) | Support tickets (type, priority, status, rating) |
| [Google Play Store Reviews](https://www.kaggle.com/datasets/lava18/google-play-store-apps) | Customer feedback text |

The datasets come from different sources, so tickets and reviews are linked
to customers at random. NPS surveys, ticket dates and resolution times are
generated, because no public dataset has them.

## Project structure

```
sql/
  01_schema.sql                 create the 4 tables
  02_load_data.sql              load the CSVs
  03_kpis.sql                   NPS, CSAT, churn, ticket summary
  04_customer_experience.sql    SLA, complaints, sentiment, at-risk customers
notebooks/
  01_data_cleaning.ipynb        clean and combine the datasets
  02_sentiment_analysis.ipynb   sentiment scoring + complaint topics
  03_customer_insights.ipynb    EDA, clustering, prediction model
```

## Tools

PostgreSQL, SQL, Python (Pandas, NumPy, Matplotlib, Scikit-learn, NLTK)

## Key findings

- NPS fell from **37.6 to 19.5** over two years, while review sentiment stayed flat.
- Slow tickets hurt satisfaction: CSAT is **3.18** for tickets fixed in under 8 hours
  and **1.44** for tickets taking over 96 hours.
- Starter-plan customers have the lowest NPS (23.6) and highest churn (42.7%).
- Among negative reviews, bugs and crashes are the biggest specific complaint (27%).
- **114** active customers are High Risk — a ready-made list for the retention team.

## How to run

1. Download the three datasets into `data/raw/`.
2. Run `notebooks/01_data_cleaning.ipynb` to create the clean CSVs.
3. Create the database and load the data:
   ```
   createdb voiceiq
   psql -d voiceiq -f sql/01_schema.sql
   psql -d voiceiq -f sql/02_load_data.sql
   ```
4. Run `notebooks/02_sentiment_analysis.ipynb`, then `03_customer_insights.ipynb`.
5. Run the analysis queries in `sql/03_kpis.sql` and `sql/04_customer_experience.sql`.
