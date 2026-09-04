-- =====================================================================================
--  schema-and-seed.sql
--  Reference schema and reproducible dataset for database-validations.sql
--  Domain: e-commerce orders and payments   |   Dialect: PostgreSQL
-- =====================================================================================
--
--  WHY THIS FILE EXISTS
--  A validation query nobody can execute is an opinion. This file lets any reviewer create the
--  schema, load a dataset that contains DELIBERATE defects, and confirm that each of the ten
--  checks in database-validations.sql returns exactly the anomalies it claims to detect.
--
--  HOW IT RELATES TO THE REST OF THE SUITE
--  tests/ui/checkout.spec.ts proves that a customer can add products to a cart and complete the
--  purchase. It cannot prove that the resulting order was persisted once rather than twice, that
--  the settled amount agrees with the payment ledger, or that a refund was not issued beyond what
--  was ever collected. Those defects live below the interface, and this is the layer that finds
--  them. The interface is green in every one of the scenarios seeded here.
--
--  Every planted defect is tagged with the query that must catch it, and every control row is
--  tagged with the query that must NOT catch it. False positives are as damaging as missed
--  defects: a check that flags healthy orders gets muted by the team within a week.
--
--  Usage:
--    psql -d qa_sandbox -f sql/schema-and-seed.sql
--    psql -d qa_sandbox -f sql/database-validations.sql
-- =====================================================================================

DROP TABLE IF EXISTS audit_log;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customer_payment_methods;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id INTEGER      PRIMARY KEY,
    email       VARCHAR(120) NOT NULL,
    full_name   VARCHAR(120) NOT NULL,
    status      VARCHAR(15)  NOT NULL,  -- ACTIVE | INACTIVE | BLOCKED
    created_at  TIMESTAMP    NOT NULL
);

CREATE TABLE customer_payment_methods (
    payment_method_id INTEGER     PRIMARY KEY,
    customer_id       INTEGER     NOT NULL REFERENCES customers (customer_id),
    method_type       VARCHAR(30) NOT NULL,  -- CARD | WALLET | BANK_TRANSFER
    status            VARCHAR(15) NOT NULL,
    registered_at     TIMESTAMP   NOT NULL
);

CREATE TABLE orders (
    order_id           INTEGER       PRIMARY KEY,
    customer_id        INTEGER       NOT NULL REFERENCES customers (customer_id),
    order_number       VARCHAR(24)   NOT NULL,
    currency           CHAR(3)       NOT NULL,
    sales_channel      VARCHAR(20)   NOT NULL,  -- WEB | MOBILE | MARKETPLACE
    status             VARCHAR(15)   NOT NULL,
    -- Goodwill authorisation. Without it, refunding more than was collected is a loss event.
    overrefund_allowed BOOLEAN       NOT NULL,
    -- Store credit or gift card value applied when the order was placed.
    prepaid_amount     NUMERIC(18,4) NOT NULL,
    -- Denormalised running total of everything settled against this order. This is the column
    -- the storefront and the finance export both read, and the one Q03 reconciles.
    settled_amount     NUMERIC(18,4) NOT NULL,
    placed_at          TIMESTAMP     NOT NULL
);

-- NOTE: payments.order_id carries NO foreign key on purpose.
-- This table is written by the payment gateway webhook consumer, out of band from the order
-- service, and the constraint is dropped so a webhook is never rejected at ingestion time. That
-- is exactly why orphan detection has to be a test: the database is no longer enforcing the
-- relationship on our behalf.
CREATE TABLE payments (
    payment_id         INTEGER       PRIMARY KEY,
    order_id           INTEGER       NOT NULL,
    external_reference VARCHAR(40)   NOT NULL,  -- reference issued by the payment provider
    payment_method     VARCHAR(20)   NOT NULL,  -- CARD | WALLET | VOUCHER | GIFT_CARD | BANK_TRANSFER
    direction          VARCHAR(6)    NOT NULL,  -- CHARGE | REFUND
    amount             NUMERIC(18,4) NOT NULL,  -- four decimals on purpose: lets rounding defects exist
    currency           CHAR(3)       NOT NULL,
    status             VARCHAR(15)   NOT NULL,  -- SETTLED | PENDING | REVERSED
    channel            VARCHAR(20)   NOT NULL,  -- WEB | MOBILE | BATCH | BACKOFFICE
    processed_at       TIMESTAMP     NOT NULL,
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
INSERT INTO customers (customer_id, email, full_name, status, created_at) VALUES
    (1, 'ada@example.com',     'Ada Lovelace',    'ACTIVE',   '2025-01-05 10:00:00'),
    (2, 'grace@example.com',   'Grace Hopper',    'ACTIVE',   '2025-01-06 10:00:00'), -- DEFECT Q04: active, no order, no payment method
    (3, 'alan@example.com',    'Alan Turing',     'INACTIVE', '2025-01-07 10:00:00'), -- CONTROL Q04: nothing linked, but inactive
    (4, 'edsger@example.com',  'Edsger Dijkstra', 'ACTIVE',   '2025-01-08 10:00:00'), -- CONTROL Q04: no order, but a saved payment method
    (5, 'barbara@example.com', 'Barbara Liskov',  'ACTIVE',   '2025-01-09 10:00:00'); -- DEFECT Q05: no purchase activity since January

INSERT INTO customer_payment_methods (payment_method_id, customer_id, method_type, status, registered_at) VALUES
    (10, 1, 'CARD',   'ACTIVE', '2025-02-01 10:00:00'),
    (11, 4, 'WALLET', 'ACTIVE', '2025-02-02 10:00:00');

-- -------------------------------------------------------------------------------------
-- ORDERS
-- Expected settled amount = prepaid_amount + sum of SETTLED movements. See Q03.
-- -------------------------------------------------------------------------------------
INSERT INTO orders (order_id, customer_id, order_number, currency, sales_channel, status, overrefund_allowed, prepaid_amount, settled_amount, placed_at) VALUES
    (1001, 1, 'ORD-2026-0001', 'EUR', 'WEB',         'FULFILLED', FALSE,   0.0000, 999.9800, '2026-09-01 08:55:00'), -- healthy: ledger reconciles
    (1002, 5, 'ORD-2026-0002', 'EUR', 'MOBILE',      'REFUNDED',  FALSE, 100.0000, -50.0000, '2026-01-15 08:50:00'), -- DEFECT Q06: refunded beyond what was collected
    (1003, 1, 'ORD-2026-0003', 'EUR', 'WEB',         'FULFILLED', TRUE,  500.0000, 600.0000, '2026-09-01 08:45:00'), -- DEFECT Q03: ledger says 650.00
    (1004, 1, 'ORD-2026-0004', 'EUR', 'MARKETPLACE', 'REFUNDED',  TRUE,    0.0000, -10.0000, '2026-09-01 07:55:00'); -- CONTROL Q06: negative but goodwill authorised

-- -------------------------------------------------------------------------------------
-- PAYMENTS
-- -------------------------------------------------------------------------------------
INSERT INTO payments (payment_id, order_id, external_reference, payment_method, direction, amount, currency, status, channel, processed_at, created_at, updated_at) VALUES
    -- Order 1001: healthy ledger, settles to 999.98
    (1,  1001, 'PSP-1001-A',   'CARD',      'CHARGE', 1000.0000, 'EUR', 'SETTLED',  'WEB',       '2026-09-01 09:00:00', '2026-09-01 09:00:00', NULL),
    (2,  1001, 'PSP-1001-B',   'CARD',      'REFUND',  250.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-09-01 10:00:00', '2026-09-01 10:00:00', NULL),
    -- DEFECT Q01 and Q07: the gateway webhook was delivered twice and ingested twice
    (6,  1001, 'PSP-DUP-001',  'WALLET',    'CHARGE',   99.9900, 'EUR', 'SETTLED',  'BATCH',     '2026-09-02 08:00:00', '2026-09-02 08:00:00', NULL),
    (7,  1001, 'PSP-DUP-001',  'WALLET',    'CHARGE',   99.9900, 'EUR', 'SETTLED',  'BATCH',     '2026-09-02 08:00:00', '2026-09-02 08:00:00', NULL),
    -- DEFECT Q07: the customer was charged twice, thirty seconds apart, under different references
    (9,  1001, 'PSP-1001-C',   'CARD',      'CHARGE',   75.0000, 'EUR', 'SETTLED',  'MOBILE',    '2026-09-02 10:00:00', '2026-09-02 10:00:00', NULL),
    (10, 1001, 'PSP-1001-D',   'CARD',      'CHARGE',   75.0000, 'EUR', 'SETTLED',  'MOBILE',    '2026-09-02 10:00:30', '2026-09-02 10:00:30', NULL),
    -- DEFECT Q08: a refund amount was mutated after creation with no audit trail
    (11, 1001, 'PSP-1001-E',   'GIFT_CARD', 'REFUND',   40.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-09-02 11:00:00', '2026-09-02 11:00:00', '2026-09-02 12:00:00'),
    -- CONTROL Q08: mutated after creation and correctly audited
    (12, 1001, 'PSP-1001-F',   'GIFT_CARD', 'REFUND',   60.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-09-02 11:30:00', '2026-09-02 11:30:00', '2026-09-02 12:30:00'),
    -- Reversed capture: excluded from reconciliation, still reported by Q10
    (18, 1001, 'PSP-1001-G',   'VOUCHER',   'CHARGE',   30.0000, 'EUR', 'REVERSED', 'BATCH',     '2026-09-02 13:00:00', '2026-09-02 13:00:00', NULL),

    -- Order 1002: no activity since January, refunded past the collected amount
    (3,  1002, 'PSP-1002-A',   'CARD',      'REFUND',  150.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-01-15 09:00:00', '2026-01-15 09:00:00', NULL),

    -- Order 1003: ledger nets +150 over 500 prepaid, so 650.00 is expected
    (4,  1003, 'PSP-1003-A',   'CARD',      'CHARGE',  200.0000, 'EUR', 'SETTLED',  'WEB',       '2026-09-01 09:00:00', '2026-09-01 09:00:00', NULL),
    (5,  1003, 'PSP-1003-B',   'CARD',      'REFUND',   50.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-09-01 09:30:00', '2026-09-01 09:30:00', NULL),

    -- Order 1004: goodwill refund, ledger reconciles
    (17, 1004, 'PSP-1004-A',   'WALLET',    'REFUND',   10.0000, 'EUR', 'SETTLED',  'BACKOFFICE','2026-09-01 08:00:00', '2026-09-01 08:00:00', NULL),

    -- DEFECT Q02: a webhook arrived for order 9999, which was never persisted
    (8,  9999, 'PSP-ORPHAN-1', 'CARD',      'CHARGE',  500.0000, 'EUR', 'SETTLED',  'BATCH',     '2026-09-01 07:00:00', '2026-09-01 07:00:00', NULL),

    -- DEFECTS Q09, kept PENDING so they never pollute the reconciliation baseline
    (13, 1001, 'PSP-AMT-ZERO',  'VOUCHER',  'CHARGE',    0.0000, 'EUR', 'PENDING',  'BATCH',     '2026-09-03 08:00:00', '2026-09-03 08:00:00', NULL),
    (14, 1001, 'PSP-AMT-NEG',   'CARD',     'CHARGE',  -25.0000, 'EUR', 'PENDING',  'BATCH',     '2026-09-03 08:10:00', '2026-09-03 08:10:00', NULL),
    (15, 1001, 'PSP-AMT-ROUND', 'VOUCHER',  'CHARGE',   10.1234, 'EUR', 'PENDING',  'BATCH',     '2026-09-03 08:20:00', '2026-09-03 08:20:00', NULL),
    (16, 1001, 'PSP-AMT-CCY',   'CARD',     'CHARGE',   50.0000, 'USD', 'PENDING',  'BATCH',     '2026-09-03 08:30:00', '2026-09-03 08:30:00', NULL);

-- Only payment 12 was audited. Payment 11 was mutated silently: that is the Q08 defect.
INSERT INTO audit_log (audit_id, entity_name, entity_id, action, changed_by, changed_at) VALUES
    (1, 'payments', 12,   'UPDATE', 'settlement_reconciler', '2026-09-02 12:30:00'),
    (2, 'orders',   1003, 'UPDATE', 'ops_console',           '2026-09-02 14:00:00');
