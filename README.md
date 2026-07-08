# SAP BusinessObjects Publications Replacement on Databricks

A complete, working demo showing how Databricks replaces SAP BusinessObjects (BO) scheduled report distribution. Built for customers migrating from BO Publications to Databricks AI/BI.

## What This Does

SAP BO Publications sends filtered reports to external recipients on a schedule. This repo replicates that capability using Databricks-native components:

```
                              ┌──────────────────────────────────┐
                              │    Unity Catalog (Governance)    │
                              │  ┌────────────┐ ┌─────────────┐ │
                              │  │ portfolio   │ │ collection  │ │
                              │  │ _data       │ │ _report     │ │
                              │  └──────┬──────┘ └──────┬──────┘ │
                              │         │               │        │
                              │  ┌──────┴───────────────┴──────┐ │
                              │  │     recipient_config        │ │
                              │  │  (who gets what + filters)  │ │
                              │  └──────────────┬──────────────┘ │
                              └─────────────────┼────────────────┘
                                                │
                    ┌────────────────────────────┴────────────────────────────┐
                    │                                                         │
          ┌─────────▼──────────┐                            ┌────────────────▼───────────┐
          │   Lakeflow Job     │                            │   Recipient Manager        │
          │   (notebook)       │                            │   (Databricks App)         │
          │                    │                            │                            │
          │  Per-recipient     │                            │  React UI to manage        │
          │  filtered reports  │                            │  recipients, filters,      │
          │  → email delivery  │                            │  and audit logs            │
          │  → audit log       │                            │                            │
          └────────────────────┘                            └────────────────────────────┘
```

### Components

| Component | BO Equivalent | What It Does |
|---|---|---|
| **Lakeflow Job** (notebook) | BO Publication | Reads config table, queries per-recipient filtered data, renders HTML/CSV/Excel, sends email |
| **Recipient Manager** (app) | BO CMC recipient management | React UI for adding/editing recipients, toggling active status, viewing audit logs |
| **Delivery Audit Log** (table) | (BO had none) | Compliance-grade log: who received what data, when, with which filters |

## Prerequisites

- Databricks workspace with Unity Catalog enabled
- Python 3.9+
- [Databricks CLI](https://docs.databricks.com/dev-tools/cli/install.html) v0.200+
- A SQL Warehouse (Serverless recommended)
- Email credentials (Gmail API, SendGrid, SES, or SMTP) stored in Databricks Secrets

## Setup (< 30 minutes)

### 1. Clone the repo

```bash
git clone https://github.com/YOUR_ORG/bo-demo.git
cd bo-demo
```

### 2. Configure Databricks CLI

```bash
databricks auth login --profile bo-demo
```

### 3. Create schema and load sample data

Open `data/setup.sql` in the Databricks SQL Editor. Replace `YOUR_CATALOG` with your catalog name, then run the entire script. This creates:

- `recipient_config` — 14 sample recipients across 8 European regions
- `portfolio_data` — 17 rows of portfolio performance data
- `collection_report` — 8 rows of monthly collection KPIs
- `delivery_audit_log` — empty, populated by the job

### 4. Import the notebook

Import `notebooks/config_driven_report_job.py` to your workspace. Update the `CATALOG` and `SCHEMA` variables in Step 0.

### 5. Configure email secrets

```bash
# For Gmail API (OAuth)
databricks secrets create-scope bo-demo --profile bo-demo
databricks secrets put-secret bo-demo gmail-client-id --string-value "YOUR_CLIENT_ID" --profile bo-demo
databricks secrets put-secret bo-demo gmail-client-secret --string-value "YOUR_SECRET" --profile bo-demo
databricks secrets put-secret bo-demo gmail-refresh-token --string-value "YOUR_TOKEN" --profile bo-demo
```

Or replace the Gmail API code with SMTP for SendGrid/SES/Office 365.

### 6. Deploy the Recipient Manager app

Update `apps/recipient-manager/app.yaml` with your workspace hostname, warehouse ID, and catalog:

```bash
# Deploy via Databricks Apps UI or CLI
databricks apps create --name recipient-manager --profile bo-demo
databricks apps deploy --name recipient-manager --source-code-path ./apps/recipient-manager --profile bo-demo
```

Grant the app's service principal access to the tables (see commented GRANT statements in `data/setup.sql`).

### 7. Run the notebook

Open the notebook in the workspace and run all cells. In `DRY_RUN = True` mode, it simulates email delivery while running the full pipeline end-to-end.

### 8. Deploy the dashboard (optional)

If you have a dashboard JSON definition, import it via the Lakeview API:

```bash
databricks api post /api/2.0/lakeview/dashboards --json '{"display_name": "Collection Performance", "serialized_dashboard": "<paste JSON>", "warehouse_id": "YOUR_WAREHOUSE_ID"}' --profile bo-demo
```

## Customizing for Your Data

1. **Add report types:** Create a new generator function in the notebook (like `generate_portfolio_summary`) and register it in `REPORT_GENERATORS`
2. **Change branding:** Edit the `render_html_report` function — colors, logo, header text
3. **Add recipients:** INSERT rows into `recipient_config` or use the Recipient Manager app
4. **Change delivery method:** Replace Gmail API with SMTP, SendGrid, SES, or Microsoft Graph
5. **Add formats:** The renderer supports HTML, CSV, Excel. Add PDF with `weasyprint`

## Cost Estimate

All pricing is Azure Premium, EU North, pay-as-you-go (list prices). Each component shows the full range from minimum (light usage, optimized settings) to maximum (heavy usage, worst-case settings).

### Pricing Rates

| SKU | $/DBU | Used by |
|-----|-------|---------|
| Jobs Serverless | $0.47 | Lakeflow Jobs (no idle tail — pay only for runtime) |
| SQL Serverless | $0.91 | Dashboard subscriptions + interactive viewing (2X-Small = 4 DBU/hr, auto-stop 5 min default / 1 min via API) |
| Interactive Serverless | $1.00 | Recipient Manager app (Medium = 0.5 DBU/hr, scales to zero when idle) |

### Component Breakdown

Each row shows a realistic range — from light usage to heavy production usage.

| Component | Light | Medium | Heavy | Formula |
|-----------|-------|--------|-------|---------|
| **Lakeflow Jobs** | **$5** | **$45** | **$188** | `runs/month × min/run ÷ 60 × 4 DBU/hr × $0.47` |
| | 12 reports, weekly, 3 min | 24 reports, mixed, 5 min | 50 reports, daily, 5 min | No idle tail — pay only for runtime |
| **Dashboard Subscriptions** | **$2** | **$6** | **$25** | `runs/month × (refresh + idle) ÷ 60 × 4 DBU/hr × $0.91` |
| | 5 dashboards, shared WH window | 10 dashboards, mostly shared | 20 dashboards, some scattered | Shared = no idle tail. Scattered = 5 min idle each |
| **Dashboard Interactive** | **$3** | **$31** | **$120** | `(query hours + idle hours) × 4 DBU/hr × $0.91` |
| | 5 users, morning only, 1-min auto-stop | 15 users, 4 clusters/day, 5-min auto-stop | 50 users, 8 clusters/day, 5-min auto-stop | Idle tail per wake-up is the main cost driver |
| **Recipient Manager App** | **$0** | **$2** | **$5** | `active hours × 0.5 DBU/hr × $1.00` |
| | Scales to zero — $0 when idle | 5x/week × 10 min | Daily use, 20 min | Scale-to-zero is the default — cost is negligible |
| **Storage** | **$0** | **$0** | **$0** | Config tables + audit log < 100 MB |
| **TOTAL** | **~$10** | **~$84** | **~$338** | |

### Scenario Summary

| Scenario | Reports | Recipients | Users | Monthly Cost |
|----------|---------|-----------|-------|-------------|
| **Light** | 12, weekly | 20 | 5 | **$10 - $25** |
| **Medium** | 24, mixed schedule | 50 | 15 | **$50 - $100** |
| **Heavy** | 50, daily | 100+ | 50 | **$200 - $340** |

### With Optimizations

| Optimization | Effect |
|-------------|--------|
| Set SQL warehouse auto-stop to 1 min (API) | Reduces interactive viewing cost by ~80% |
| Batch all subscriptions right after Jobs | Eliminates subscription idle tail entirely |
| Databricks commit (enterprise agreement) | 30-50% discount on all DBU rates |
| All three combined | Typical drops from **$84 to ~$25/month** |

### vs SAP BusinessObjects (50 users)

| | SAP BO | Databricks |
|---|---|---|
| User licenses | $1,250-2,500/month | **$0** (no per-seat fees) |
| Server infrastructure | $500-2,000/month | **Included** in serverless DBU rate |
| Admin / developer | $500-1,000/month | **Self-service** — config table + app |
| **Monthly total** | **$2,250-5,500** | **$10-340** |
| **Annual total** | **$27,000-66,000** | **$120-4,100** |
| **Savings** | — | **94-99%** |

Adding more recipients costs $0 — the Job runs one query per filter combination, not per email. SAP BO 4.3 reaches end of maintenance December 2026.

See `docs/COST_ESTIMATE.md` for the full model with detailed formulas and sensitivity analysis.

## Repository Structure

```
bo-demo-repo/
├── README.md                          # This file
├── LICENSE                            # Custom demo license
├── .gitignore
├── databricks.yml                     # DABs bundle for deployment
├── notebooks/
│   └── config_driven_report_job.py    # Main Lakeflow Job notebook
├── apps/
│   └── recipient-manager/
│       ├── main.py                    # FastAPI backend
│       ├── frontend/
│       │   └── index.html             # React frontend (single file)
│       ├── app.yaml                   # Databricks App config
│       └── requirements.txt
├── data/
│   └── setup.sql                      # Schema + sample data
├── dashboard/
│   └── (import via API — see setup)
├── decks/
│   └── *.html                              # Amplify presentation deck
└── docs/
    ├── COST_ESTIMATE.md               # Cost model with formulas
    └── DAIS_2026_Features.md          # Feature research for BO migration
```

## Related Resources

- [Manage scheduled dashboard updates and subscriptions](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/schedule-subscribe)
- [Embed dashboards for external users](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/embedding/external-embed)
- [Databricks Asset Bundles](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/)
- SAP BO 4.3 reaches end of maintenance December 2026
