# BO Replacement — Monthly Cost Estimate

**Prepared by:** Your Name, Solutions Architect
**Date:** July 2026
**Region:** Azure EU North (Nordics)
**Status:** PRELIMINARY — based on initial scoping estimates, pending the customer's sizing questionnaire response

---

## Assumptions (To Be Validated)

These numbers come from our initial scoping calls (May-June 2026). The customer has not yet returned the sizing questionnaire. All figures marked with (*) are estimates that should be validated.

| Parameter | Estimated Value | Source |
|-----------|----------------|--------|
| BO reports to migrate | ~24 (*) | Playbook question — not yet confirmed |
| Scheduled report runs per day | 50-100 (*) | Amplify deck assumption — not confirmed |
| Total recipients | 20-50 (*) | Amplify deck assumption — not confirmed |
| BO universes (semantic layers) | 3+ | Confirmed by the customer (May 25 scoping call) |
| Recipients are external | Yes | Confirmed — not in Entra ID |
| Countries/regions | ~8 (up to 22) | 8 in demo data, the customer operates in 22 countries |
| Data volume per report | Small (< 100 rows per filtered query) | Based on demo data structure |

**What we DON'T know yet:**
- Exact number of reports
- How many are broadcast (same data to all) vs per-recipient filtered
- Exact recipient count per report
- Frequency per report (daily, weekly, monthly, or mixed)
- Report complexity (simple tables vs multi-page with charts)
- Data volume per report at production scale

---

## Pricing Rates (Azure Premium, EU North)

All rates are list prices (pay-as-you-go). Commitment/enterprise agreements typically reduce these by 30-50%.

| SKU | $/DBU | Source |
|-----|-------|--------|
| SQL Serverless | $0.91 | `system.billing.list_prices` — `PREMIUM_SERVERLESS_SQL_COMPUTE` |
| Jobs Serverless | $0.47 | `system.billing.list_prices` — `PREMIUM_JOBS_SERVERLESS_COMPUTE` |
| Interactive Serverless (Apps) | $1.00 | `system.billing.list_prices` — `PREMIUM_ALL_PURPOSE_SERVERLESS_COMPUTE` |

**SQL Warehouse size:** 2X-Small (Starter) = **4 DBU/hr** while running

---

## How Serverless SQL Billing Works

- The warehouse consumes **4 DBU/hr at a fixed rate** while in RUNNING state — whether or not a query is executing.
- After queries finish, the warehouse idles until the **auto-stop timer** expires, then stops and consumption goes to zero.
- **Serverless auto-stop minimum: 5 minutes** (via UI) or **1 minute** (via API). Much shorter than classic warehouses.
- **Startup time: 2-6 seconds.** Fast enough that aggressive auto-stop is practical.
- There is **no per-query billing** and **no separate Azure VM bill** — everything is included in the DBU rate.

**Core formula:**
```
Monthly cost = (active hours/month) × (DBU/hr) × ($/DBU)
Active hours = query time + idle tail per wake-up
Cost per wake-up = (query minutes + 5 min idle) / 60 × 4 DBU/hr × $0.91
```

**Example:** 1 wake-up, 2 min of queries + 5 min idle = 7 min = $0.43

---

## Cost Model — Based on Estimated Report Volume

### Scenario: ~24 Reports, 50-100 Runs/Day, 20-50 Recipients

We model this as a daily batch: all reports run in a single window (e.g., 06:00-07:00 every morning), keeping the warehouse warm once.

---

### Component 1: Config-Driven Lakeflow Jobs (~24 reports)

**What it does:** Each report is a Lakeflow Job running on **serverless Jobs compute**. It reads the recipient config, runs SQL queries per recipient via `spark.sql()`, renders output (HTML/CSV/Excel), and sends emails.

**Important:** The Lakeflow Job runs entirely on **serverless Jobs compute** ($0.47/DBU) — not on a SQL warehouse. The `spark.sql()` calls execute on the Jobs cluster itself. No SQL warehouse is involved.

**Key modeling decision:** Not all 24 reports run every day. Typical BO schedules are a mix:

| Frequency | Reports (*) | Runs/month | Recipients per run (*) |
|-----------|-------------|------------|----------------------|
| Daily | 8 | 8 × 30 = 240 | 10-20 each |
| Weekly | 10 | 10 × 4 = 40 | 20-30 each |
| Monthly | 6 | 6 × 1 = 6 | 30-50 each |
| **Total** | **24** | **286 runs/month** | **Avg ~20** |

**Per run:** Each job queries ~20 recipients × 1 query each on small data, renders reports, sends emails. Estimated total runtime: ~5 min per run (query + render + send).

**Jobs compute cost:**

Serverless Jobs compute starts in seconds and bills for actual runtime only. No idle tail — the cluster is released as soon as the job finishes.

```
Daily jobs (8 reports × 30 days):
  240 runs × 5 min = 1,200 min = 20 hr

Weekly jobs (10 reports × 4 weeks):
  40 runs × 5 min = 200 min = 3.33 hr

Monthly jobs (6 reports × 1):
  6 runs × 8 min = 48 min = 0.80 hr

Total Jobs compute: 20 + 3.33 + 0.80 = 24.13 hr
24.13 hr × 4 DBU/hr = 96.52 DBU
96.52 DBU × $0.47 = $45.36/month
```

**Note:** Serverless Jobs compute has no idle tail — you only pay for the time the job is actually running. This is a significant cost advantage over running queries through a SQL warehouse.

**Subtotal: $45.36/month**

---

### Component 2: AI/BI Dashboard Subscriptions (broadcast reports)

**What it does:** For reports where everyone gets the same data (no per-recipient filtering), native subscriptions handle delivery with zero code. We estimate ~40% of the 24 reports are broadcast.

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Broadcast reports | ~10 (*) | ~40% of 24 reports — common split per industry benchmarks |
| Dashboards to subscribe | ~10 | One dashboard per broadcast report |
| Subscription frequency | Mixed (daily/weekly) | Same mix as above |
| Subscription runs/month | ~100 | 5 daily × 30 + 5 weekly × 4 |
| Refresh time per run | ~1 min | 5-6 widgets, small data |

**SQL Warehouse cost (scheduled back-to-back with Lakeflow Jobs):**

```
Subscription refreshes run in the same daily window as Jobs.
Incremental query time: 100 runs × 1 min = 100 min = 1.67 hr
No extra idle tail (warehouse already warm from Jobs).
1.67 hr × 4 DBU/hr = 6.68 DBU
6.68 DBU × $0.91 = $6.08/month
```

**No per-delivery fee.** Sending to 20 or 100 recipients costs the same — the query runs once.

**Subtotal: $6.08/month**

---

### Component 3: Dashboard Interactive Viewing

**What it does:** Country managers and internal users open dashboards to explore data interactively.

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Interactive users | 15 (*) | 10 country managers + 5 internal |
| Dashboards viewed | ~10 of 24 (the ones with interactive value) | Not all reports need interactive access |
| Views per week | 50 (*) | ~3 per user |
| Views per month | 200 | — |
| Query time per view | ~20 sec (5 widgets on small data) | Estimated |
| Wake-ups per day | ~4 (*) | Morning, midday, afternoon, end of day |
| Idle tail per wake-up | 5 min | Serverless minimum |

**SQL Warehouse cost:**

```
Query time: 200 views × 20 sec = 4,000 sec = 67 min = 1.11 hr
Idle tail: 4 wake-ups/day × 22 workdays × 5 min = 440 min = 7.33 hr
Total: 1.11 + 7.33 = 8.44 hr
8.44 hr × 4 DBU/hr = 33.76 DBU
33.76 DBU × $0.91 = $30.72/month
```

**Note:** If users view dashboards during the morning window when the Lakeflow Jobs already warmed the warehouse, the idle tail overlaps. Realistic cost may be 30-50% lower.

**Subtotal: ~$30.72/month** (worst case)

---

### Component 4: Recipient Manager App

**What it does:** Admin manages recipients, filters, and reviews audit logs. Scales to zero when not in use.

| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Uses per month | 20 (5x/week) | Admin tasks: add/edit recipients, review audit log |
| Duration per use | 10 min | Estimated |
| App compute size | Medium (0.5 DBU/hr) | Default |

**App compute cost (scale-to-zero — $0 when idle):**

```
20 uses × 10 min = 200 min = 3.33 hr
3.33 hr × 0.5 DBU/hr = 1.67 DBU
1.67 DBU × $1.00 = $1.67/month
```

**Subtotal: $1.67/month**

---

### Component 5: Storage

| Table | Rows (at scale) | Size |
|-------|-----------------|------|
| recipient_config | ~50-100 | < 10 KB |
| ~24 report data tables | Varies — likely 100-10K rows each | < 10 MB total |
| delivery_audit_log | ~286 entries/day × 365 = ~104K/yr | < 50 MB |
| Dashboard definitions | 10-24 dashboards | Metadata only |

**Cost: < $0.10/month.** Negligible even at scale.

---

## Summary — Estimated Monthly Cost (~24 Reports)

| Component | Compute type | How it's calculated | DBU/month | $/month |
|-----------|-------------|-------------------|-----------|---------|
| **Lakeflow Jobs** (24 reports, 286 runs/mo) | Jobs Serverless ($0.47) | 24.1 hr × 4 DBU/hr — no idle tail | 97 | **$45.36** |
| **Dashboard Subscriptions** (10 broadcast) | SQL Serverless ($0.91) | 1.67 hr × 4 DBU/hr (back-to-back) | 7 | **$6.08** |
| **Dashboard interactive** (15 users) | SQL Serverless ($0.91) | 8.44 hr × 4 DBU/hr (incl. idle tail) | 34 | **$30.72** |
| **Recipient Manager App** | Interactive Serverless ($1.00) | 3.33 hr × 0.5 DBU/hr (scale-to-zero) | 2 | **$1.67** |
| **Storage** | — | < 100 MB total | — | **< $0.10** |
| **TOTAL** | | | **~140 DBU** | **~$84/month** |

---

## Sensitivity Analysis

| Scenario | Change | Monthly Cost |
|----------|--------|-------------|
| **Base estimate** | As above (24 reports, 50 recipients) | **~$84** |
| **Optimized scheduling** | Subscriptions in Job window, users view during same window | **~$60** |
| **Auto-stop at 1 min** (API) | SQL WH idle tail drops from 5 min to 1 min (Jobs unaffected — no idle tail) | **~$55** |
| **With Databricks commit** (40% discount) | All DBU rates × 0.6 | **~$50** |
| **Commit + 1 min auto-stop** | Both optimizations | **~$35** |
| **Larger volume** (50 reports, 100 recipients) | 2× Jobs compute, same SQL WH pattern | **~$130** |
| **Smaller volume** (12 reports, 20 recipients) | Half Jobs compute | **~$60** |

---

## vs SAP BusinessObjects

| | SAP BO (50 users) | Databricks (~24 reports, 50 recipients) |
|---|---|---|
| User licenses | $1,250-2,500/month | $0 (no per-seat fees) |
| Server infrastructure | $500-2,000/month | Included in serverless DBU rate |
| BO admin / Crystal Reports developer | $500-1,000/month (partial FTE) | Self-service, config-driven |
| **Monthly total** | **$2,250-5,500** | **~$84** (list) / **~$50** (commit) |
| **Annual total** | **$27,000-66,000** | **~$600-1,000** |
| **Savings** | — | **96-98%** |

**SAP BO 4.3 reaches end of maintenance December 2026** — migration is not optional.

---

## Caveats and Disclaimers

1. **These estimates are preliminary.** They are based on initial scoping conversations (May-June 2026), not confirmed inventory data from the customer. The sizing questionnaire has been sent but not yet returned. Actual costs will be refined once we have: exact report count, recipient lists, frequency per report, data volume per query, and report complexity.

2. **Serverless SQL warehouse** — all estimates assume a serverless SQL warehouse with auto-stop at 5 minutes. Serverless eliminates VM management, includes infrastructure costs in the DBU rate ($0.91), and starts in 2-6 seconds. There is no separate Azure VM bill. Setting auto-stop to 1 minute (via API) would reduce idle costs by ~80%.

3. **Batch scheduling is key.** The cost model assumes all daily reports run in a single morning window (e.g., 06:00-07:00), sharing one warehouse warm session. If reports run at scattered times throughout the day, each independent wake-up adds a 5-minute idle tail (~$0.30 per wake-up). Scattered scheduling could increase costs by 50-100%.

4. **Data volume is assumed small.** If production report queries return 10K+ rows or join large tables, query times will increase. This model assumes < 100 rows per filtered query based on the demo data structure.

5. **No per-seat licensing.** Adding 100 new recipients costs $0 in Databricks compute. The Lakeflow Job runs the same number of queries regardless of whether you email 10 or 100 people (the query runs once per region/filter, not once per email). Dashboard Subscriptions similarly run the query once and broadcast the result.

6. **With a Databricks commit** (enterprise agreement), DBU rates are typically 30-50% lower. The estimates above use list prices. With a 40% commit discount, the monthly cost drops to ~$64.

7. **Incremental cost only.** These numbers represent the incremental cost of the BO replacement workload. They do not include the customer's existing Databricks consumption (DWH migration, Modern Data Platform, etc.) which already covers the base SQL warehouse usage.

8. **The Lakeflow Job is the bridge.** When Databricks ships native report bursting (~Q4 FY27), the Job becomes optional for most reports. The data layer (tables, Metric Views, dashboards) built now is exactly what native bursting will use. No wasted investment.

---

## What We Need from the Customer to Refine This Estimate

1. Complete the sizing questionnaire (sent June 2026)
2. Provide a BO report inventory: report name, frequency, recipient count, filter type
3. Confirm how many reports are broadcast vs per-recipient filtered
4. Share sample data volumes (row counts for the tables behind the top 5 reports)
5. Confirm the production schedule — single morning batch or scattered throughout the day?
