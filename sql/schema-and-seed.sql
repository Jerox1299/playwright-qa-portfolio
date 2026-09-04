-- =====================================================================================
--  schema-and-seed.sql
--  Reference schema and reproducible dataset for database-validations.sql
--  Dialect: PostgreSQL
-- =====================================================================================
--
--  WHY THIS FILE EXISTS
--  A validation query nobody can execute is an opinion. This file lets any reviewer create
--  the schema, load a dataset that contains DELIBERATE defects, and confirm that each of the
--  ten checks in database-validations.sql returns exactly the anomalies it claims to detect.
--
--  Every planted defect is tagged below with the query that must catch it, and every control
--  row is tagged with the query that must NOT catch it. False positives are as damaging as
--  missed defects: a check that flags healthy accounts gets muted by the team within a week.
--
--  Usage:
--    psql -d qa_sandbox -f sql/schema-and-seed.sql
--    psql -d qa_sandbox -f sql/database-validations.sql
-- =====================================================================================

DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customer_products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id     INTEGER      PRIMARY KEY,
    document_number VARCHAR(20)  NOT NULL,
    full_name       VARCHAR(120) NOT NULL,
    status          VARCHAR(15)  NOT NULL,  -- ACTIVE | INACTIVE | BLOCKED
    created_at      TIMESTAMP    NOT NULL
);

CREATE TABLE customer_products (
    product_id   INTEGER     PRIMARY KEY,
    customer_id  INTEGER     NOT NULL REFERENCES customers (customer_id),
    product_type VARCHAR(30) NOT NULL,      -- CREDIT_CARD | MORTGAGE | INSURANCE
    status       VARCHAR(15) NOT NULL,
    opened_at    TIMESTAMP   NOT NULL
);

CREATE TABLE accounts (
    account_id        INTEGER       PRIMARY KEY,
    customer_id       INTEGER       NOT NULL REFERENCES customers (customer_id),
    account_number    VARCHAR(24)   NOT NULL,
    currency          CHAR(3)       NOT NULL,
    account_type      VARCHAR(20)   NOT NULL,
    status            VARCHAR(15)   NOT NULL,
    overdraft_allowed BOOLEAN       NOT NULL,
    opening_balance   NUMERIC(18,4) NOT NULL,
    current_balance   NUMERIC(18,4) NOT NULL,
    opened_at         TIMESTAMP     NOT NULL
);

-- NOTE: transactions.account_id carries NO foreign key on purpose.
-- In real banking estates this table is fed by batch ingestion from core systems and the
-- constraint is dropped for load performance. That is exactly why orphan detection has to be
-- a test: the database is no longer enforcing the relationship on our behalf.
CREATE TABLE transactions (
    transaction_id     INTEGER       PRIMARY KEY,
    account_id         INTEGER       NOT NULL,
    external_reference VARCHAR(40)   NOT NULL,
    transaction_type   VARCHAR(20)   NOT NULL,  -- SALARY | TRANSFER | FEE | WITHDRAWAL | REFUND
    direction          VARCHAR(6)    NOT NULL,  -- DEBIT | CREDIT
    amount             NUMERIC(18,4) NOT NULL,  -- four decimals on purpose: lets rounding defects exist
    currency           CHAR(3)       NOT NULL,
    status             VARCHAR(15)   NOT NULL,  -- POSTED | PENDING | REVERSED
    channel            VARCHAR(20)   NOT NULL,
    posted_at          TIMESTAMP     NOT NULL,
    created_at         TIMESTAMP     NOT NULL,
    updated_at         TIMESTAMP
);

CREATE TABLE audit_log (
    audit_id    INTEGER     PRIMARY KEY,
    entity_name VARCHAR(40) NOT NULL,
    entity_id   INTEGER     NOT NULL,
    action      VARCHAR(10) NOT NULL,  -- INSERT | UPDATE | DELETE
    changed_by  VARCHAR(40) NOT NULL,
    changed_at  TIMESTAMP   NOT NULL
);

-- -------------------------------------------------------------------------------------
-- CUSTOMERS
-- -------------------------------------------------------------------------------------
INSERT INTO customers (customer_id, document_number, full_name, status, created_at) VALUES
    (1, 'DOC-0001', 'Ada Lovelace',    'ACTIVE',   '2025-01-05 10:00:00'),
    (2, 'DOC-0002', 'Grace Hopper',    'ACTIVE',   '2025-01-06 10:00:00'), -- DEFECT Q04: active, no product, no account
    (3, 'DOC-0003', 'Alan Turing',     'INACTIVE', '2025-01-07 10:00:00'), -- CONTROL Q04: nothing linked, but inactive
    (4, 'DOC-0004', 'Edsger Dijkstra', 'ACTIVE',   '2025-01-08 10:00:00'), -- CONTROL Q04: no account, but holds a product
    (5, 'DOC-0005', 'Barbara Liskov',  'ACTIVE',   '2025-01-09 10:00:00'); -- DEFECT Q05: dormant since January

INSERT INTO customer_products (product_id, customer_id, product_type, status, opened_at) VALUES
    (10, 1, 'CREDIT_CARD', 'ACTIVE', '2025-02-01 10:00:00'),
    (11, 4, 'INSURANCE',   'ACTIVE', '2025-02-02 10:00:00');

-- -------------------------------------------------------------------------------------
-- ACCOUNTS
-- Expected balance = opening_balance + sum of POSTED movements. See Q03.
-- -------------------------------------------------------------------------------------
INSERT INTO accounts (account_id, customer_id, account_number, currency, account_type, status, overdraft_allowed, opening_balance, current_balance, opened_at) VALUES
    (1001, 1, 'ES7620770024001', 'EUR', 'CHECKING', 'ACTIVE', FALSE,   0.0000, 500.0200, '2025-01-10 10:00:00'), -- healthy: ledger reconciles
    (1002, 5, 'ES7620770024002', 'EUR', 'CHECKING', 'ACTIVE', FALSE, 100.0000, -50.0000, '2025-02-01 10:00:00'), -- DEFECT Q06: negative without overdraft
    (1003, 1, 'ES7620770024003', 'EUR', 'SAVINGS',  'ACTIVE', TRUE,  500.0000, 600.0000, '2025-02-10 10:00:00'), -- DEFECT Q03: ledger says 650.00
    (1004, 1, 'ES7620770024004', 'EUR', 'CHECKING', 'ACTIVE', TRUE,    0.0000, -10.0000, '2025-03-01 10:00:00'); -- CONTROL Q06: negative but authorised

-- -------------------------------------------------------------------------------------
-- TRANSACTIONS
-- -------------------------------------------------------------------------------------
INSERT INTO transactions (transaction_id, account_id, external_reference, transaction_type, direction, amount, currency, status, channel, posted_at, created_at, updated_at) VALUES
    -- Account 1001: healthy ledger, sums to 500.02
    (1,  1001, 'REF-1001-A',    'SALARY',     'CREDIT', 1000.0000, 'EUR', 'POSTED',   'CORE',   '2026-09-01 09:00:00', '2026-09-01 09:00:00', NULL),
    (2,  1001, 'REF-1001-B',    'TRANSFER',   'DEBIT',   250.0000, 'EUR', 'POSTED',   'MOBILE', '2026-09-01 10:00:00', '2026-09-01 10:00:00', NULL),
    -- DEFECT Q01 and Q07: identical composite key ingested twice
    (6,  1001, 'REF-DUP-001',   'FEE',        'DEBIT',    99.9900, 'EUR', 'POSTED',   'BATCH',  '2026-09-02 08:00:00', '2026-09-02 08:00:00', NULL),
    (7,  1001, 'REF-DUP-001',   'FEE',        'DEBIT',    99.9900, 'EUR', 'POSTED',   'BATCH',  '2026-09-02 08:00:00', '2026-09-02 08:00:00', NULL),
    -- DEFECT Q07: same amount and type, thirty seconds apart, different reference
    (9,  1001, 'REF-1001-C',    'WITHDRAWAL', 'DEBIT',    75.0000, 'EUR', 'POSTED',   'ATM',    '2026-09-02 10:00:00', '2026-09-02 10:00:00', NULL),
    (10, 1001, 'REF-1001-D',    'WITHDRAWAL', 'DEBIT',    75.0000, 'EUR', 'POSTED',   'ATM',    '2026-09-02 10:00:30', '2026-09-02 10:00:30', NULL),
    -- DEFECT Q08: mutated after creation with no audit trail
    (11, 1001, 'REF-1001-E',    'REFUND',     'CREDIT',   40.0000, 'EUR', 'POSTED',   'CORE',   '2026-09-02 11:00:00', '2026-09-02 11:00:00', '2026-09-02 12:00:00'),
    -- CONTROL Q08: mutated after creation and correctly audited
    (12, 1001, 'REF-1001-F',    'REFUND',     'CREDIT',   60.0000, 'EUR', 'POSTED',   'CORE',   '2026-09-02 11:30:00', '2026-09-02 11:30:00', '2026-09-02 12:30:00'),
    -- Reversed movement: excluded from reconciliation, still reported by Q10
    (18, 1001, 'REF-1001-G',    'FEE',        'DEBIT',    30.0000, 'EUR', 'REVERSED', 'BATCH',  '2026-09-02 13:00:00', '2026-09-02 13:00:00', NULL),

    -- Account 1002: dormant since January, drives the balance negative
    (3,  1002, 'REF-1002-A',    'TRANSFER',   'DEBIT',   150.0000, 'EUR', 'POSTED',   'BRANCH', '2026-01-15 09:00:00', '2026-01-15 09:00:00', NULL),

    -- Account 1003: ledger nets +150 over an opening balance of 500, so 650.00 is expected
    (4,  1003, 'REF-1003-A',    'SALARY',     'CREDIT',  200.0000, 'EUR', 'POSTED',   'CORE',   '2026-09-01 09:00:00', '2026-09-01 09:00:00', NULL),
    (5,  1003, 'REF-1003-B',    'TRANSFER',   'DEBIT',    50.0000, 'EUR', 'POSTED',   'MOBILE', '2026-09-01 09:30:00', '2026-09-01 09:30:00', NULL),

    -- Account 1004: authorised overdraft, ledger reconciles
    (17, 1004, 'REF-1004-A',    'WITHDRAWAL', 'DEBIT',    10.0000, 'EUR', 'POSTED',   'ATM',    '2026-09-01 08:00:00', '2026-09-01 08:00:00', NULL),

    -- DEFECT Q02: account 9999 does not exist
    (8,  9999, 'REF-ORPHAN-1',  'TRANSFER',   'CREDIT',  500.0000, 'EUR', 'POSTED',   'BATCH',  '2026-09-01 07:00:00', '2026-09-01 07:00:00', NULL),

    -- DEFECTS Q09, kept PENDING so they never pollute the reconciliation baseline
    (13, 1001, 'REF-AMT-ZERO',  'FEE',        'DEBIT',     0.0000, 'EUR', 'PENDING',  'BATCH',  '2026-09-03 08:00:00', '2026-09-03 08:00:00', NULL),
    (14, 1001, 'REF-AMT-NEG',   'TRANSFER',   'DEBIT',   -25.0000, 'EUR', 'PENDING',  'BATCH',  '2026-09-03 08:10:00', '2026-09-03 08:10:00', NULL),
    (15, 1001, 'REF-AMT-ROUND', 'FEE',        'DEBIT',    10.1234, 'EUR', 'PENDING',  'BATCH',  '2026-09-03 08:20:00', '2026-09-03 08:20:00', NULL),
    (16, 1001, 'REF-AMT-CCY',   'TRANSFER',   'DEBIT',    50.0000, 'USD', 'PENDING',  'BATCH',  '2026-09-03 08:30:00', '2026-09-03 08:30:00', NULL);

-- Only transaction 12 was audited. Transaction 11 was mutated silently: that is the Q08 defect.
INSERT INTO audit_log (audit_id, entity_name, entity_id, action, changed_by, changed_at) VALUES
    (1, 'transactions', 12, 'UPDATE', 'etl_settlement_job', '2026-09-02 12:30:00'),
    (2, 'accounts',   1003, 'UPDATE', 'ops_console',        '2026-09-02 14:00:00');
