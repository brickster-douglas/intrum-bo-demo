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

Running ~24 reports with 50 recipients on serverless compute:

| Component | Monthly Cost |
|---|---|
| Lakeflow Jobs (serverless) | ~$45 |
| Dashboard subscriptions | ~$6 |
| Dashboard interactive viewing | ~$31 |
| Recipient Manager app | ~$2 |
| **Total (list price)** | **~$84/month** |

With a Databricks commit (40% discount) and 1-minute auto-stop: **~$35/month**.

See `docs/COST_ESTIMATE.md` for the full model with formulas and sensitivity analysis.

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
