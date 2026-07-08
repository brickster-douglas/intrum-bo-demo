# BO Replacement — Monthly Cost Estimate

**Prepared by:** Your Name, Solutions Architect
**Date:** July 2026
**Region:** Azure EU North (Nordics)
**Status:** PRELIMINARY — based on initial scoping estimates, pending the customer's sizing questionnaire response

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
```

---

## Cost Model — Min / Max Range per Component

Each component is modeled with a **minimum** (optimized scheduling, low usage, 1-min auto-stop) and **maximum** (scattered usage, heavy interactive viewing, 5-min auto-stop) scenario.

---

### Component 1: Config-Driven Lakeflow Jobs

**Compute type:** Jobs Serverless ($0.47/DBU) — no idle tail, pay only for runtime.

| Scenario | Reports | Runs/month | Runtime/run | Total hours | DBUs | $/month |
|----------|---------|-----------|-------------|-------------|------|---------|
| **Minimum** (12 reports, weekly) | 12 | 48 | 3 min | 2.4 hr | 9.6 | **$4.51** |
| **Typical** (24 reports, mixed daily/weekly/monthly) | 24 | 286 | 5 min | 24.1 hr | 96.5 | **$45.36** |
| **Maximum** (50 reports, mostly daily, complex) | 50 | 1,200 | 10 min | 200 hr | 800 | **$376.00** |

**Formula:** `runs/month × minutes/run ÷ 60 × 4 DBU/hr × $0.47`

**Why there's no idle tail:** Serverless Jobs compute is released immediately when the job finishes. You pay only for actual processing time.

---

### Component 2: AI/BI Dashboard Subscriptions

**Compute type:** SQL Serverless ($0.91/DBU). Cost depends on whether subscriptions share a warehouse warm window with other activity.

| Scenario | Dashboards | Runs/month | Refresh time | Idle tail | Total hours | DBUs | $/month |
|----------|-----------|-----------|-------------|-----------|-------------|------|---------|
| **Minimum** (few dashboards, back-to-back with Jobs) | 5 | 40 | 1 min | 0 min (shared) | 0.67 hr | 2.7 | **$2.43** |
| **Typical** (10 dashboards, mostly back-to-back) | 10 | 100 | 1 min | 0 min (shared) | 1.67 hr | 6.7 | **$6.08** |
| **Maximum** (20 dashboards, separate schedules, 5-min idle each) | 20 | 200 | 2 min | 5 min | 23.3 hr | 93.3 | **$84.93** |

**Formula:** `runs/month × (refresh_min + idle_min) ÷ 60 × 4 DBU/hr × $0.91`

**Key insight:** If subscriptions run right after the Lakeflow Jobs (e.g., 07:05 after the job at 07:00), the warehouse is already warm — no idle tail cost. Scattered scheduling is significantly more expensive.

---

### Component 3: Dashboard Interactive Viewing

**Compute type:** SQL Serverless ($0.91/DBU). Cost is dominated by the idle tail per warehouse wake-up, not the actual query time.

| Scenario | Users | Views/month | Query time/view | Wake-ups/day | Idle tail | Total hours | DBUs | $/month |
|----------|-------|-------------|----------------|-------------|-----------|-------------|------|---------|
| **Minimum** (few users, clustered morning view, 1-min auto-stop) | 5 | 40 | 15 sec | 1 | 1 min | 0.83 hr | 3.3 | **$3.03** |
| **Typical** (15 users, 4 clusters/day, 5-min auto-stop) | 15 | 200 | 20 sec | 4 | 5 min | 8.44 hr | 33.8 | **$30.72** |
| **Maximum** (50 users, continuous use during business hours) | 50 | 1,000 | 20 sec | always-on 8hr/day | N/A | 176 hr | 704 | **$640.64** |

**Formula:** `(views × sec/view ÷ 3600 + wake-ups/day × workdays × idle_min ÷ 60) × 4 DBU/hr × $0.91`

**Why the range is so wide:** The minimum assumes 5 users checking once a day in the morning (1 wake-up, 1-min auto-stop = $3/month). The maximum assumes 50 users viewing throughout the day keeping the warehouse running continuously during business hours (8 hr/day × 22 days = $641/month). The typical case is in between.

---

### Component 4: Recipient Manager App

**Compute type:** Interactive Serverless ($1.00/DBU). Medium app = 0.5 DBU/hr. Scales to zero when idle.

| Scenario | Usage pattern | Active hours/month | DBUs | $/month |
|----------|-------------|-------------------|------|---------|
| **Minimum** (occasional admin use, scale-to-zero) | 2x/week × 5 min | 0.67 hr | 0.33 | **$0.33** |
| **Typical** (regular admin use, scale-to-zero) | 5x/week × 10 min | 3.33 hr | 1.67 | **$1.67** |
| **Maximum** (always-on, no scale-to-zero, 24/7) | 24 × 30 = 720 hr | 720 hr | 360 | **$360.00** |

**Formula:** `active_hours × 0.5 DBU/hr × $1.00`

**Why the range is so wide:** With scale-to-zero (default), the app costs pennies — it only runs when someone opens it. If you disable scale-to-zero and keep it running 24/7 (for instant response time), it costs $360/month. There is no reason to run it 24/7 for an admin tool used a few times a week.

---

### Component 5: Storage

| Scenario | Data volume | $/month |
|----------|------------|---------|
| **All scenarios** | < 100 MB (config tables + audit log) | **< $0.10** |

Storage is negligible regardless of usage pattern. Even with 100K audit log entries per year, the data is under 100 MB.

---

## Summary — Monthly Cost Range

| Component | Compute | Min | Typical | Max | What drives the range |
|-----------|---------|-----|---------|-----|----------------------|
| **Lakeflow Jobs** | Jobs ($0.47) | **$5** | **$45** | **$376** | Number of reports × frequency × complexity |
| **Subscriptions** | SQL ($0.91) | **$2** | **$6** | **$85** | Shared vs scattered scheduling |
| **Interactive views** | SQL ($0.91) | **$3** | **$31** | **$641** | User count × usage pattern × auto-stop setting |
| **Recipient Manager** | Apps ($1.00) | **$0** | **$2** | **$5** | Scale-to-zero (default) — cost is negligible |
| **Storage** | — | **$0** | **$0** | **$0** | Negligible |
| **TOTAL** | | **~$10** | **~$84** | **~$338** | |

Note: the "Max" column reflects realistic heavy production usage (50 reports daily, 50 active users). Theoretical maximum (e.g., always-on app 24/7, warehouse running continuously) would be higher but is not a realistic deployment pattern.

### With optimizations applied

| Optimization | Effect on typical cost |
|-------------|----------------------|
| 1-min auto-stop (API setting) | Typical drops from $84 to ~$55 |
| Databricks commit (40% discount) | Typical drops from $84 to ~$50 |
| Both optimizations | Typical drops to **~$35** |
| Both + batch scheduling | **~$25** |

---

## Realistic Range for Most Customers

The min and max above include extreme scenarios (always-on app, 50 continuous users). For a realistic deployment:

| Scenario | Description | Monthly Cost |
|----------|-------------|-------------|
| **Light** | 12 reports, weekly, 5 users, scale-to-zero | **$10 - $25** |
| **Medium** | 24 reports, mixed schedule, 15 users | **$50 - $100** |
| **Heavy** | 50 reports, daily, 50 users, interactive portal | **$200 - $340** |

With a Databricks commit: multiply by 0.6.

---

## vs SAP BusinessObjects

| | SAP BO (50 users) | Databricks (typical) | Databricks (range) |
|---|---|---|---|
| User licenses | $1,250-2,500/month | $0 | $0 |
| Server infrastructure | $500-2,000/month | Included | Included |
| Admin / developer | $500-1,000/month | Self-service | Self-service |
| **Monthly total** | **$2,250-5,500** | **~$84** | **$10-500** |
| **Annual total** | **$27,000-66,000** | **~$1,000** | **$120-6,000** |
| **Savings** | — | **96-98%** | **90-99%** |

**Key advantage:** No per-seat licensing. Adding 100 more recipients costs $0. Cost scales with compute usage, not with user count.

**SAP BO 4.3 reaches end of maintenance December 2026.**

---

## Caveats and Disclaimers

1. **These estimates are preliminary.** Based on initial scoping, not confirmed inventory data. Actual costs depend on: exact report count, recipient lists, frequency, data volume, and query complexity.

2. **Serverless SQL warehouse** — all estimates assume serverless compute. No separate Azure VM bill. Auto-stop at 5 minutes (default) or 1 minute (API setting). Startup in 2-6 seconds.

3. **Batch scheduling is the single biggest cost lever.** Running all reports in one morning window vs scattered throughout the day can mean 2-3× difference in SQL warehouse cost.

4. **Data volume is assumed small.** If production queries return 10K+ rows or join large tables, job runtimes increase and the cost shifts toward the upper end of the range.

5. **No per-seat licensing.** Adding recipients costs $0 in compute. The job runs one query per filter combination, not per email address.

6. **With a Databricks commit** (enterprise agreement), DBU rates are typically 30-50% lower. Apply a 0.6× multiplier to all estimates for committed pricing.

7. **Incremental cost only.** These numbers are for the BO replacement workload only. They do not include existing Databricks consumption (DWH migration, analytics, etc.).

8. **The Lakeflow Job is the bridge.** When native report bursting ships (~Q4 FY27), the Job becomes optional for most reports. The data layer built now is exactly what native bursting will use. No wasted investment.
