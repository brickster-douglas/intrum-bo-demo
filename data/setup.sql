-- ============================================================================
-- BO Demo — Schema & Sample Data Setup
-- ============================================================================
-- Replace YOUR_CATALOG with your Unity Catalog catalog name.
-- Run this in a Databricks SQL Editor or notebook.
-- ============================================================================

-- Step 1: Create Schema
CREATE SCHEMA IF NOT EXISTS YOUR_CATALOG.bo_demo
COMMENT 'SAP BusinessObjects Publications replacement demo';

USE CATALOG YOUR_CATALOG;
USE SCHEMA bo_demo;

-- ============================================================================
-- Step 2: Create Tables
-- ============================================================================

-- Recipient configuration — the control plane for report distribution
CREATE TABLE IF NOT EXISTS recipient_config (
    recipient_id INT NOT NULL COMMENT 'Unique recipient ID',
    recipient_name STRING NOT NULL COMMENT 'Display name',
    email STRING NOT NULL COMMENT 'Delivery email address',
    company STRING NOT NULL COMMENT 'Company or business unit',
    region STRING NOT NULL COMMENT 'Geographic region',
    report_type STRING NOT NULL COMMENT 'Report type: portfolio_summary, collection_report',
    filter_column STRING COMMENT 'Column used for filtering (e.g., region)',
    filter_value STRING COMMENT 'Filter value (e.g., Sweden)',
    filters STRING COMMENT 'JSON array of filter conditions',
    format STRING NOT NULL COMMENT 'Output format: PDF, CSV, Excel',
    is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Whether recipient is active',
    updated_at TIMESTAMP DEFAULT current_timestamp() COMMENT 'Last updated'
) COMMENT 'Recipient configuration for config-driven report distribution. Each row defines who gets what report with which filters.';

-- Portfolio data — source for the Portfolio Summary report
CREATE TABLE IF NOT EXISTS portfolio_data (
    region STRING NOT NULL COMMENT 'Geographic region',
    client_name STRING NOT NULL COMMENT 'Client or debtor segment',
    portfolio_type STRING NOT NULL COMMENT 'Portfolio classification',
    total_cases INT NOT NULL COMMENT 'Number of active cases',
    total_outstanding_eur DOUBLE NOT NULL COMMENT 'Total outstanding balance in EUR',
    collected_eur DOUBLE NOT NULL COMMENT 'Total collected in EUR',
    collection_rate DOUBLE NOT NULL COMMENT 'Collection rate (0-1)',
    avg_days_to_collect INT NOT NULL COMMENT 'Average days to collect',
    month_date DATE NOT NULL COMMENT 'Reporting month'
) COMMENT 'Portfolio-level collection data by region and client. Source for the Portfolio Summary report.';

-- Collection performance report data
CREATE TABLE IF NOT EXISTS collection_report (
    region STRING NOT NULL COMMENT 'Geographic region',
    month_date DATE NOT NULL COMMENT 'Reporting month',
    new_cases INT NOT NULL COMMENT 'New cases opened this month',
    closed_cases INT NOT NULL COMMENT 'Cases closed this month',
    total_collected_eur DOUBLE NOT NULL COMMENT 'EUR collected this month',
    recovery_rate DOUBLE NOT NULL COMMENT 'Recovery rate (0-1)',
    avg_resolution_days INT NOT NULL COMMENT 'Average days to resolve',
    top_performer STRING NOT NULL COMMENT 'Top performing agent this month'
) COMMENT 'Monthly collection performance by region. Source for the Collection Report.';

-- Delivery audit log — compliance-grade tracking of all report deliveries
CREATE TABLE IF NOT EXISTS delivery_audit_log (
    delivery_id STRING NOT NULL COMMENT 'Unique delivery event ID',
    recipient_id INT NOT NULL COMMENT 'FK to recipient_config',
    recipient_name STRING NOT NULL,
    email STRING NOT NULL,
    report_type STRING NOT NULL,
    region_filter STRING COMMENT 'Region filter applied',
    format STRING NOT NULL COMMENT 'Output format: PDF, CSV, Excel',
    row_count INT COMMENT 'Number of data rows in the report',
    file_size_bytes INT COMMENT 'Size of the generated report',
    status STRING NOT NULL COMMENT 'SUCCESS, FAILED, SKIPPED, DRY_RUN',
    error_message STRING COMMENT 'Error details if status=FAILED',
    delivered_at TIMESTAMP NOT NULL COMMENT 'Delivery timestamp',
    execution_duration_ms INT COMMENT 'Time to generate + deliver'
) COMMENT 'Audit trail for all report deliveries. Query this to answer: who received what, when, and with which data filters.';

-- ============================================================================
-- Step 3: Insert Sample Recipient Config (14 recipients across 8 regions)
-- ============================================================================

INSERT INTO recipient_config VALUES
(1,  'Anna Lindqvist',        'anna.lindqvist@example.com',    'Acme Collections SE',   'Sweden',      'portfolio_summary',  'region', 'Sweden',      '[{"column":"region","operator":"=","value":"Sweden"}]',      'PDF',   true, current_timestamp()),
(2,  'Erik Berg',              'erik.berg@example.com',         'Acme Collections SE',   'Sweden',      'collection_report',  'region', 'Sweden',      '[{"column":"region","operator":"=","value":"Sweden"}]',      'Excel', true, current_timestamp()),
(3,  'Marco Rossi',            'marco.rossi@example.com',      'Acme Collections IT',   'Italy',       'portfolio_summary',  'region', 'Italy',       '[{"column":"region","operator":"=","value":"Italy"}]',       'PDF',   true, current_timestamp()),
(4,  'Elena Bianchi',          'elena.bianchi@example.com',     'Acme Collections IT',   'Italy',       'collection_report',  'region', 'Italy',       '[{"column":"region","operator":"=","value":"Italy"}]',       'CSV',   true, current_timestamp()),
(5,  'Piotr Kowalski',         'piotr.kowalski@example.com',   'Acme Collections PL',   'Poland',      'portfolio_summary',  'region', 'Poland',      '[{"column":"region","operator":"=","value":"Poland"}]',      'Excel', true, current_timestamp()),
(6,  'Dimitris Papadopoulos',  'dimitris.p@example.com',       'Acme Collections GR',   'Greece',      'portfolio_summary',  'region', 'Greece',      '[{"column":"region","operator":"=","value":"Greece"}]',      'PDF',   true, current_timestamp()),
(7,  'Lars Andersen',          'lars.andersen@example.com',     'Acme Collections NO',   'Norway',      'collection_report',  'region', 'Norway',      '[{"column":"region","operator":"=","value":"Norway"}]',      'CSV',   true, current_timestamp()),
(8,  'Sophie van Dijk',        'sophie.vandijk@example.com',   'Acme Collections NL',   'Netherlands', 'portfolio_summary',  'region', 'Netherlands', '[{"column":"region","operator":"=","value":"Netherlands"}]', 'PDF',   true, current_timestamp()),
(9,  'Pablo Martinez',         'pablo.martinez@example.com',   'Acme Collections ES',   'Spain',       'collection_report',  'region', 'Spain',       '[{"column":"region","operator":"=","value":"Spain"}]',      'Excel', true, current_timestamp()),
(10, 'Liisa Virtanen',         'liisa.virtanen@example.com',   'Acme Collections FI',   'Finland',     'portfolio_summary',  'region', 'Finland',     '[{"column":"region","operator":"=","value":"Finland"}]',     'PDF',   true, current_timestamp()),
(11, 'Jan Svensson',           'jan.svensson@example.com',     'Nexer AB',    'Sweden',      'portfolio_summary',  'region', 'Sweden',      '[{"column":"region","operator":"=","value":"Sweden"}]',      'CSV',   false, current_timestamp()),
(12, 'Maria Korhonen',         'maria.korhonen@example.com',   'Acme Collections FI',   'Finland',     'collection_report',  'region', 'Finland',     '[{"column":"region","operator":"=","value":"Finland"}]',     'Excel', true, current_timestamp()),
(13, 'Willem Peters',          'willem.peters@example.com',    'Acme Collections NL',   'Netherlands', 'collection_report',  'region', 'Netherlands', '[{"column":"region","operator":"=","value":"Netherlands"}]', 'CSV',   true, current_timestamp()),
(14, 'Carmen Garcia',          'carmen.garcia@example.com',    'Acme Collections ES',   'Spain',       'portfolio_summary',  'region', 'Spain',       '[{"column":"region","operator":"=","value":"Spain"}]',      'PDF',   false, current_timestamp());

-- ============================================================================
-- Step 4: Insert Sample Portfolio Data (17 rows across 8 regions)
-- ============================================================================

INSERT INTO portfolio_data VALUES
('Sweden',      'Nordic Consumer AB',        'Consumer',    1250, 12500000.00, 9000000.00, 0.72, 45, '2026-06-01'),
('Sweden',      'Scandinavian Credit Corp',  'Commercial',   380, 8200000.00,  5740000.00, 0.70, 52, '2026-06-01'),
('Sweden',      'Stockholm Retail Group',    'Unsecured',    620, 4100000.00,  2870000.00, 0.70, 48, '2026-06-01'),
('Italy',       'Milano Collections SpA',    'Consumer',    2100, 18500000.00, 7770000.00, 0.42, 95, '2026-06-01'),
('Italy',       'Roma Credit Services',      'Commercial',   890, 14200000.00, 5680000.00, 0.40, 102, '2026-06-01'),
('Poland',      'Warsaw Financial Group',    'Consumer',    1800, 9800000.00,  5390000.00, 0.55, 68, '2026-06-01'),
('Poland',      'Krakow Debt Solutions',     'Secured',      450, 6700000.00,  3685000.00, 0.55, 72, '2026-06-01'),
('Greece',      'Athens Recovery SA',        'Consumer',    3200, 22100000.00, 8398000.00, 0.38, 118, '2026-06-01'),
('Greece',      'Thessaloniki Credit',       'Government',   670, 5400000.00,  2052000.00, 0.38, 125, '2026-06-01'),
('Norway',      'Bergen Inkasso AS',         'Consumer',     980, 10200000.00, 7140000.00, 0.70, 42, '2026-06-01'),
('Norway',      'Oslo Credit Services',      'Commercial',   310, 5600000.00,  3920000.00, 0.70, 47, '2026-06-01'),
('Netherlands', 'Amsterdam Collections BV',  'Consumer',    1100, 11800000.00, 7552000.00, 0.64, 55, '2026-06-01'),
('Netherlands', 'Rotterdam Credit NV',       'Secured',      520, 7900000.00,  5056000.00, 0.64, 58, '2026-06-01'),
('Spain',       'Madrid Cobros SL',          'Consumer',    2400, 16300000.00, 7824000.00, 0.48, 85, '2026-06-01'),
('Spain',       'Barcelona Credit Services', 'Unsecured',    780, 5100000.00,  2448000.00, 0.48, 90, '2026-06-01'),
('Finland',     'Helsinki Perintatoimisto',   'Consumer',     870, 7600000.00,  5016000.00, 0.66, 50, '2026-06-01'),
('Finland',     'Turku Financial Oy',        'Commercial',   290, 3200000.00,  2112000.00, 0.66, 53, '2026-06-01');

-- ============================================================================
-- Step 5: Insert Sample Collection Report Data (8 rows — one per region)
-- ============================================================================

INSERT INTO collection_report VALUES
('Sweden',      '2026-06-01', 180, 165, 2850000.00, 0.72, 42, 'Anna Lindqvist'),
('Italy',       '2026-06-01', 420, 290, 1950000.00, 0.42, 98, 'Luca Romano'),
('Poland',      '2026-06-01', 310, 235, 1680000.00, 0.55, 65, 'Agnieszka Nowak'),
('Greece',      '2026-06-01', 480, 280, 1250000.00, 0.38, 115, 'Nikos Papadopoulos'),
('Norway',      '2026-06-01', 150, 140, 2400000.00, 0.70, 40, 'Lars Andersen'),
('Netherlands', '2026-06-01', 200, 170, 2100000.00, 0.64, 52, 'Pieter Janssen'),
('Spain',       '2026-06-01', 380, 265, 1580000.00, 0.48, 82, 'Pablo Martinez'),
('Finland',     '2026-06-01', 130, 115, 1850000.00, 0.66, 48, 'Mikko Virtanen');

-- ============================================================================
-- Step 6: Grant Access to Databricks App Service Principal (optional)
-- Replace YOUR_SERVICE_PRINCIPAL_UUID with your app's service principal UUID.
-- ============================================================================

-- GRANT USE SCHEMA ON SCHEMA YOUR_CATALOG.bo_demo TO `YOUR_SERVICE_PRINCIPAL_UUID`;
-- GRANT SELECT ON TABLE YOUR_CATALOG.bo_demo.recipient_config TO `YOUR_SERVICE_PRINCIPAL_UUID`;
-- GRANT MODIFY ON TABLE YOUR_CATALOG.bo_demo.recipient_config TO `YOUR_SERVICE_PRINCIPAL_UUID`;
-- GRANT SELECT ON TABLE YOUR_CATALOG.bo_demo.delivery_audit_log TO `YOUR_SERVICE_PRINCIPAL_UUID`;
-- GRANT SELECT ON TABLE YOUR_CATALOG.bo_demo.portfolio_data TO `YOUR_SERVICE_PRINCIPAL_UUID`;
-- GRANT SELECT ON TABLE YOUR_CATALOG.bo_demo.collection_report TO `YOUR_SERVICE_PRINCIPAL_UUID`;

-- ============================================================================
-- Verify
-- ============================================================================

SELECT 'recipient_config' AS table_name, COUNT(*) AS row_count FROM YOUR_CATALOG.bo_demo.recipient_config
UNION ALL
SELECT 'portfolio_data', COUNT(*) FROM YOUR_CATALOG.bo_demo.portfolio_data
UNION ALL
SELECT 'collection_report', COUNT(*) FROM YOUR_CATALOG.bo_demo.collection_report;
