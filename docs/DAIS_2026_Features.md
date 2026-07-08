# New Databricks Features for SAP BO Migration — DAIS 2026 Update

**Audience:** Technical team familiar with SAP BusinessObjects, new to Databricks
**Prepared by:** Your Name, Solutions Architect
**Date:** July 2026

---

## Introduction

The customer is migrating from SAP BusinessObjects Publications to Databricks AI/BI Dashboards. The core challenge is not just recreating reports — it is replicating the BO publication engine: scheduled, personalized delivery of reports to recipients who are often outside the company's identity system (country managers, external partners, regional teams across Europe).

In June 2026, we demoed a config-driven Lakeflow Job to solve the personalized delivery problem. That solution is still the right backbone for per-recipient filtered delivery. But since that demo, several features have shipped that close the remaining gaps — and change what still needs custom code.

This document summarizes what's new, what it means for the customer specifically, and how the recommended architecture has changed.

---

## Section 1: The Big Wins

These features directly address gaps we flagged in the June demo.

---

### 1.1 Dashboard Subscriptions Now Reach External Recipients

**What it is:** Previously, only users with a Databricks account could be added as subscribers to a scheduled dashboard. External email addresses were not supported. That is now changed — admins can configure "notification destinations" (any email address, including distribution lists and external users) and dashboard authors can add them as subscribers.

**How it works:**
- Workspace admin defines notification destinations (external email addresses, DLs) under workspace settings
- Dashboard author creates a schedule and adds those destinations as subscribers
- On each run, recipients receive a PDF snapshot of the dashboard

**Why it matters for the customer:** This was the single biggest limitation we flagged in June. BO Publications sends reports to country managers who do not have Databricks accounts — and there was no native way to do that. Now the subscription system can reach them directly. For broadcast scenarios (everyone gets the same report), no custom job is needed.

**What it does not do:** Every subscriber gets the same view. If the Sweden country manager needs to see Swedish data only and the Italy country manager needs Italian data only, subscriptions cannot filter per recipient. That is still the job of the Lakeflow Job.

**Reference:** [Manage scheduled dashboard updates and subscriptions](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/schedule-subscribe)

---

### 1.2 Data Attachments in Subscription Emails (CSV, TSV, Excel)

**What it is:** Subscription emails can now include raw data exports from dashboard widgets — not just a PDF image of the report.

**How it works:**
- When configuring a subscription schedule, the author selects which widgets to attach and chooses the format: CSV, TSV, or Excel
- Up to 100,000 rows per attachment
- Tabular attachments work for email subscriptions; Slack and Teams subscriptions receive PDF only

**Why it matters for the customer:** BO Publications sends data files — formatted Excel sheets or CSVs that recipients open and work with. A PDF screenshot alone is not a replacement. Now Databricks subscriptions can deliver the same types of attachments. A country manager receives both the visual PDF and the underlying data in Excel. That closes a significant functional gap.

**Reference:** [Manage scheduled dashboard updates and subscriptions](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/schedule-subscribe)

---

### 1.3 Full CI/CD for Dashboards and Genie Spaces

**What it is:** Declarative Automation Bundles (DABs — Databricks' infrastructure-as-code tool) now support AI/BI Dashboards and Genie Spaces as deployable resources. This means dashboards and spaces are defined in version-controlled YAML files alongside pipelines and jobs, and promoted through dev → test → prod using a standard CI/CD pipeline.

**How it works:**

```yaml
# databricks.yml (simplified)
resources:
  dashboards:
    collection_dashboard:
      display_name: "Collection Dashboard"
      file_path: ../src/collection.lvdash.json
      warehouse_id: ${var.warehouse_id}
  genie_spaces:
    portfolio_genie:
      title: "Portfolio Performance"
      warehouse_id: ${var.warehouse_id}
      file_path: ./portfolio.geniespace.json
```

When deployed to dev, it uses `dev_catalog.dev_schema`. When deployed to prod, it uses `prod_catalog.prod_schema`. Same dashboard definition, different data. Promotion happens through your normal pipeline (GitHub Actions, Azure DevOps, etc.).

**Why it matters for the customer:** The team asked about CI/CD for dashboards on May 29. This is the answer. No more manual copy-paste between environments. Dashboards are version-controlled, testable, and promoted exactly like the rest of the data pipeline. This is how you manage 50+ reports across multiple countries at production quality.

**Note:** Requires the DABs direct deployment engine (`bundle: engine: direct`), which becomes the default on July 24, 2026.

**Reference:** [Declarative Automation Bundles overview](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/) | [Bundle resources (dashboards + Genie Spaces)](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/resources)

---

## Section 2: Strengthens the Migration Story

These features are not blockers, but they make the migration faster, more complete, and closer to BO parity.

---

### 2.1 Dashboard Relationships — Multi-Fact Data Models

**What it is:** Build complex data models that join multiple tables, scoped to a single dashboard, without publishing anything to Unity Catalog first.

**Background:** BO uses "universes" — pre-built data models that join multiple tables and define business logic. The Databricks equivalent is Metric Views (see 2.5 below), but those live in Unity Catalog and require a publish step. Dashboard Relationships give you a lighter-weight option: define the join logic directly inside the dashboard editor, without touching the catalog.

**Why it matters:** For rapid prototyping or one-off reports, Dashboard Relationships let the team build multi-table reports without waiting for a Metric View to be published. Useful during the migration sprint when recreating BO WebI reports quickly.

**Status:** Public Preview (July 1, 2026)

**Reference:** [Dashboard relationships](https://learn.microsoft.com/en-us/azure/databricks/dashboards/manage/data-modeling/dashboard-relationships/)

---

### 2.2 Genie Code — Natural Language Dashboard Authoring

**What it is:** Describe a dashboard in plain language and Genie Code generates the SQL datasets, visualizations, filters, and layout automatically. This is a full agentic authoring mode — the AI plans, builds, and asks for your approval at each step.

**Example prompts:**
- "Create a dashboard showing collection performance by country using `@portfolio_data`"
- "Build a counter showing total outstanding balance for Q2"
- "Add a date range filter that applies to all charts on this page"

**Why it matters for the customer:** Rebuilding 50+ BO WebI reports as AI/BI Dashboards is a significant effort. Genie Code accelerates this — describe the report in words and let the AI generate it. Not 100% accurate on the first pass, but it dramatically reduces the time to create the initial draft. Use it to generate, then refine.

**Status:** Generally Available (May 28, 2026)

**Reference:** [Use Genie Code for dashboard authoring](https://learn.microsoft.com/en-us/azure/databricks/dashboards/manage/dashboard-agent)

---

### 2.3 Import Power BI and Tableau Reports as AI/BI Dashboards

**What it is:** Upload a Power BI (`.pbix`, `.pbit`) or Tableau (`.twb`, `.twbx`) file and Genie Code converts it into an AI/BI Dashboard connected to your Unity Catalog data. It recreates visualizations and generates Metric Views for the underlying business logic.

**Why it matters for the customer:** While there is no direct BO importer (see Section 3), if any reports exist in Power BI or Tableau format from the broader DWH modernization, they can be imported directly. This is also relevant if the customer has any QlikView reports that have been converted to Power BI at any point. Reduces migration effort to near-zero for those reports.

**Status:** Generally Available (July 2, 2026). Beta through June, promoted to GA at DAIS.

**Reference:** [Import BI files using Genie Code](https://learn.microsoft.com/en-us/azure/databricks/dashboards/manage/import-bi)

---

### 2.4 Metric Views — Improvements Closing the BO Universe Gap

**What it is:** Metric Views are the Databricks equivalent of BO Universes — a governed semantic layer that sits between raw tables and reports. They define business logic once (joins, measures, dimensions) and reuse it across dashboards and Genie Spaces.

Several improvements shipped in May–June 2026 that make Metric Views more capable:

| Improvement | What it does | BO Equivalence |
|---|---|---|
| **Parameters** | Dynamic inputs that change query behavior based on user selection (e.g., date range picker) | BO prompts / dynamic filters |
| **Wildcard expressions** | Inherit all fields from a source table without listing them one by one | BO "all objects from table" shortcut |
| **JOIN...RELY** | Declare trusted join relationships between tables without explicit foreign keys | BO join cardinality hints |
| **Median and Percentile** | New aggregate expressions available in the low-code editor | BO formula editor functions |
| **Local Metric Views** | Create Metric Views directly inside a dashboard without publishing to Unity Catalog | BO universe-per-report pattern |

**Why it matters for the customer:** Each of these closes a specific functional gap versus BO Universes. The more parity Metric Views have with BO Universes, the more accurately the team can replicate existing report logic without writing raw SQL.

**Reference:** [Create and edit metric views](https://learn.microsoft.com/en-us/azure/databricks/business-semantics/metric-views/create-edit)

---

### 2.5 Subscription Delivery to Slack and Microsoft Teams

**What it is:** Dashboard subscriptions can push PDF snapshots and dashboard links to Slack channels or Microsoft Teams channels on a schedule. The channel receives a PNG image preview directly in the channel feed, plus a PDF attachment in the thread.

**Why it matters for the customer:** Internal teams often prefer receiving operational reports where they already work — in Teams or Slack — rather than checking email. This is a zero-code delivery channel. No custom job needed. Relevant for internal distribution lists that currently receive BO publications by email.

**Reference:** [Manage scheduled dashboard updates and subscriptions](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/schedule-subscribe)

---

### 2.6 Custom Email Subject Lines for Subscriptions

**What it is:** Dashboard authors can set custom subject lines on subscription emails. Previously the subject was always "Dashboard: [dashboard name]".

**Why it matters for the customer:** Small but important for BO parity. BO emails have branded subjects like "Monthly Portfolio Report — AT" or "Q2 Collection Summary — SE". Now Databricks subscription emails can match that branding. Recipients recognize what they are receiving before opening.

**Reference:** [Manage scheduled dashboard updates and subscriptions](https://learn.microsoft.com/en-us/azure/databricks/dashboards/share/schedule-subscribe)

---

## Section 3: What Is Still Missing

Be honest with the customer about the remaining gaps. Do not oversell.

| Gap | Status | Workaround |
|---|---|---|
| **Native report bursting** — automatically send different data to different recipients with no code | On roadmap. No confirmed GA date. | Config-driven Lakeflow Job (our demo). Works today, fully governed, tested. |
| **BO WebI / Crystal Reports importer** — upload a `.wid` file and get an AI/BI Dashboard | Does not exist. No announcement. | Genie Code authoring (manual prompt-driven recreation). Faster than scratch, but still manual. |
| **Per-recipient row filtering in subscriptions** — send different filtered views to different subscribers from the same schedule | Not available. | Lakeflow Job with per-recipient query logic. |

The Lakeflow Job is still required for any scenario involving personalized data per recipient. Subscriptions are for broadcast — everyone gets the same view. That distinction matters for the customer's use case and should be communicated clearly.

---

## Section 4: Updated Architecture Recommendation

### Before — June 2026 (what we demoed)

| Tier | Pattern | Handles |
|---|---|---|
| 1 | Config-driven Lakeflow Job | ALL scheduled report delivery — internal + external, personalized or broadcast |
| 2 | AI/BI Dashboard Subscriptions | Internal broadcast only (Databricks users only) |
| 3 | Dashboard Embedding (`external_value`) | Interactive self-service portal for external users |

### After — July 2026 (with new features)

| Tier | Pattern | Handles |
|---|---|---|
| 1 | Config-driven Lakeflow Job | Per-recipient filtered delivery (still the backbone for personalized reports) |
| 2a | Dashboard Subscriptions — Email + CSV/Excel | Broadcast delivery to internal AND external recipients |
| 2b | Dashboard Subscriptions — Slack / Teams | Internal team channels |
| 3 | Dashboard Embedding (`external_value`) | Interactive self-service portal with per-user data filtering |
| 4 | DABs CI/CD | Dev → Test → Prod promotion for all dashboards and spaces |

**Bottom line:** The Lakeflow Job is still the backbone for personalized delivery. Nothing has changed there. What has changed is that fewer recipients need it. For recipients who all get the same view — regardless of whether they have a Databricks account — native subscriptions now handle it, including data attachments and external email addresses. The self-service layer is GA. The CI/CD layer is GA. The migration path is now end-to-end producible without gaps.

---

## Section 5: Next Steps

| # | Action | Owner |
|---|---|---|
| 1 | Update the demo deck to show native subscription with external recipient and Excel attachment | SA |
| 2 | Add a live subscription demo — schedule a dashboard, add an external email, show the delivery | SA |
| 3 | Build a DABs CI/CD example — dev → prod dashboard promotion with parameterized catalog | SA |
| 4 | Share this document with customer ahead of next session | SA |
| 5 | Confirm customer's internal comms tooling — Teams or Slack — to tailor the subscription demo | AE |

---

*All features listed are live in Azure Databricks as of July 2026. Release dates and GA status sourced directly from [Azure Databricks June 2026 release notes](https://learn.microsoft.com/en-us/azure/databricks/release-notes/product/2026/june), [July 2026 release notes](https://learn.microsoft.com/en-us/azure/databricks/release-notes/product/2026/july), and [AI/BI 2026 release notes](https://learn.microsoft.com/en-us/azure/databricks/ai-bi/release-notes/2026).*
