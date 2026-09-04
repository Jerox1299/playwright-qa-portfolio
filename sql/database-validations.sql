-- =====================================================================================
--  database-validations.sql
--  Ten data validation checks for an e-commerce orders and payments platform
--  Dialect: PostgreSQL   |   Schema and seeded defects: sql/schema-and-seed.sql
-- =====================================================================================
--
--  HOW TO READ THIS FILE
--  Each check states the test case, the risk it mitigates, the SQL technique it relies on and
--  the result that means "pass". Eight of the ten are assertions: an empty result set is a pass
--  and every returned row is a defect report ready to attach to a ticket. Two of them, Q05 and
--  Q10, are reports rather than assertions, and their headers say so explicitly.
--
--  WHY THIS LAYER EXISTS
--  tests/ui/checkout.spec.ts drives a real purchase through the storefront and asserts that the
--  order is confirmed. That test passes in every scenario seeded here, because the storefront
--  reads back the same row it wrote. It cannot see that the gateway webhook was ingested twice,
--  that the settled amount disagrees with the payment ledger, or that a refund exceeded what was
--  ever collected. Those are the defects that reach the finance close, the chargeback queue and
--  the customer's card statement, and this is the layer that catches them.
--
--  Run these against a restored production-like snapshot in a lower environment. Never against
--  production without an explicit read-only role and a signed-off change window.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- Q01. LOGICAL DUPLICATES ON A COMPOSITE PAYMENT KEY
-- -------------------------------------------------------------------------------------
-- Test case:   the same payment movement must never be persisted twice for one order.
-- Risk:        the payment provider retries a webhook and the consumer ingests it twice, so the
--              customer is charged twice for one basket. The primary key hides it because each
--              copy receives its own surrogate id, so uniqueness must be asserted on the BUSINESS
--              key, which is the provider reference, not on the technical one.
-- Technique:   GROUP BY on the composite business key with HAVING COUNT(*) > 1, plus STRING_AGG
--              so the report names the offending ids instead of only counting them.
-- Pass:        zero rows.
SELECT
    p.order_id,
    p.external_reference,
    p.amount,
    p.processed_at,
    COUNT(*)                                                   AS occurrences,
    STRING_AGG(p.payment_id::TEXT, ', ' ORDER BY p.payment_id) AS duplicated_ids
FROM payments p
GROUP BY p.order_id, p.external_reference, p.amount, p.processed_at
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, p.order_id;


-- -------------------------------------------------------------------------------------
-- Q02. ORPHAN PAYMENTS WITH NO PARENT ORDER
-- -------------------------------------------------------------------------------------
-- Test case:   every payment must belong to an order that exists.
-- Risk:        broken referential integrity. Money was captured from a customer against an order
--              nobody owns, so it never appears in the order history, support cannot refund it
--              from the back office, and it still lands in the settlement totals.
-- Technique:   anti-join, expressed as LEFT JOIN plus IS NULL on the right-hand key. Preferred
--              over NOT IN because NOT IN silently returns nothing when the subquery yields a
--              NULL, which is a classic way to write a check that can never fail.
-- Pass:        zero rows.
SELECT
    p.payment_id,
    p.order_id AS missing_order_id,
    p.external_reference,
    p.amount,
    p.currency,
    p.processed_at
FROM payments p
LEFT JOIN orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
ORDER BY p.processed_at;


-- -------------------------------------------------------------------------------------
-- Q03. SETTLEMENT RECONCILIATION: STORED ORDER TOTAL AGAINST THE PAYMENT LEDGER
-- -------------------------------------------------------------------------------------
-- Test case:   the settled amount stored on the order must equal the prepaid amount plus every
--              settled payment movement.
-- Risk:        the highest impact defect on this platform. The denormalised column is what the
--              storefront shows the customer and what the finance export reports, and it drifts
--              from its ledger after a failed rollback or a partially applied migration. The
--              customer sees one figure, accounting reconciles another, and nobody can say which
--              of the two is authoritative.
-- Technique:   aggregation inside a CTE, signed with CASE WHEN so charges add and refunds
--              subtract, then compared with a tolerance. The tolerance is deliberate: exact
--              equality on decimals turns every legitimate rounding cent into a false alarm.
-- Pass:        zero rows.
WITH ledger AS (
    SELECT
        p.order_id,
        SUM(CASE WHEN p.direction = 'CHARGE' THEN p.amount ELSE -p.amount END) AS net_settled
    FROM payments p
    WHERE p.status = 'SETTLED'   -- pending and reversed movements are not part of the total
    GROUP BY p.order_id
)
SELECT
    o.order_id,
    o.order_number,
    o.settled_amount,
    o.prepaid_amount + COALESCE(l.net_settled, 0)                        AS expected_amount,
    o.settled_amount - (o.prepaid_amount + COALESCE(l.net_settled, 0))   AS difference
FROM orders o
LEFT JOIN ledger l ON l.order_id = o.order_id
WHERE ABS(o.settled_amount - (o.prepaid_amount + COALESCE(l.net_settled, 0))) > 0.01
ORDER BY ABS(o.settled_amount - (o.prepaid_amount + COALESCE(l.net_settled, 0))) DESC;


-- -------------------------------------------------------------------------------------
-- Q04. ACTIVE CUSTOMERS WITH NO ORDER AND NO SAVED PAYMENT METHOD
-- -------------------------------------------------------------------------------------
-- Test case:   an active customer must have placed at least one order or saved at least one
--              payment method.
-- Risk:        a registration flow that commits the customer record and then fails before the
--              first order or the payment method is stored leaves a ghost account. It inflates
--              the active customer figure that marketing reports on, and it blocks the person
--              from registering again with the same address.
-- Technique:   two chained LEFT JOINs with IS NULL on both sides, so the check demands the
--              absence of BOTH relationships rather than either one.
-- Pass:        zero rows.
SELECT
    c.customer_id,
    c.email,
    c.full_name,
    c.status,
    c.created_at
FROM customers c
LEFT JOIN orders                   o ON o.customer_id = c.customer_id
LEFT JOIN customer_payment_methods m ON m.customer_id = c.customer_id
WHERE c.status = 'ACTIVE'
  AND o.order_id IS NULL
  AND m.payment_method_id IS NULL
ORDER BY c.customer_id;


-- -------------------------------------------------------------------------------------
-- Q05. MOST RECENT PAYMENT PER CUSTOMER, WITH DORMANCY FLAG
-- -------------------------------------------------------------------------------------
-- Test case:   report, not assertion. Returns exactly one row per customer, the latest movement.
-- Risk:        reactivation campaigns, churn reporting and stored-card expiry policies are all
--              driven by last purchase activity. Getting "latest" wrong by one row misclassifies
--              the customer and the campaign targets the wrong segment.
-- Technique:   ROW_NUMBER() OVER (PARTITION BY customer ORDER BY processed_at DESC) filtered to 1.
--              ROW_NUMBER is the right function here because exactly one row per customer is
--              required. DENSE_RANK would return every movement tied on the same timestamp,
--              which is the correct choice for "all top ranked" but wrong for "the latest one".
--              The tie breaker on payment_id makes the result deterministic when two movements
--              share a timestamp, which is what keeps this query repeatable.
-- Pass:        one row per customer holding at least one settled movement.
WITH ranked_activity AS (
    SELECT
        c.customer_id,
        c.full_name,
        p.payment_id,
        p.payment_method,
        p.amount,
        p.processed_at,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_id
            ORDER BY p.processed_at DESC, p.payment_id DESC
        ) AS recency_rank
    FROM customers c
    JOIN orders   o ON o.customer_id = c.customer_id
    JOIN payments p ON p.order_id    = o.order_id
    WHERE p.status = 'SETTLED'
)
SELECT
    customer_id,
    full_name,
    payment_id   AS last_payment_id,
    payment_method,
    amount,
    processed_at AS last_activity_at,
    (CURRENT_DATE - processed_at::DATE) AS days_since_last_activity,
    CASE
        WHEN (CURRENT_DATE - processed_at::DATE) > 90 THEN 'DORMANT'
        ELSE 'ACTIVE'
    END AS activity_flag
FROM ranked_activity
WHERE recency_rank = 1
ORDER BY days_since_last_activity DESC;


-- -------------------------------------------------------------------------------------
-- Q06. NEGATIVE SETTLED AMOUNT ON ORDERS WITH NO OVER-REFUND AUTHORISATION
-- -------------------------------------------------------------------------------------
-- Test case:   an order may only settle below zero when a goodwill over-refund is authorised.
-- Risk:        the platform refunded more money than it ever collected for that basket. It is a
--              direct financial loss and a known fraud vector, and it usually means the refund
--              path never validated the remaining refundable amount.
-- Technique:   predicate combining the state column with the business permission flag. The query
--              joins the customer so the report is actionable by the operations team instead of
--              being a list of anonymous identifiers.
-- Pass:        zero rows.
SELECT
    o.order_id,
    o.order_number,
    c.full_name,
    o.settled_amount,
    o.overrefund_allowed,
    o.status
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.settled_amount < 0
  AND o.overrefund_allowed = FALSE
ORDER BY o.settled_amount;


-- -------------------------------------------------------------------------------------
-- Q07. REPEATED MOVEMENTS IN A SHORT WINDOW: DOUBLE CHARGE OR REPLAY
-- -------------------------------------------------------------------------------------
-- Test case:   one order must not receive two identical movements within sixty seconds.
-- Risk:        a retried request with no idempotency key, or a replayed message from the payment
--              queue, charges the customer twice for the same basket. This one is not detectable
--              by comparing the business key, because the second capture legitimately carries a
--              different provider reference. It is the defect behind most "I was charged twice"
--              support tickets.
-- Technique:   LAG() over a named window partitioned by order, method and amount, ordered by
--              time, then the elapsed seconds between neighbours. A self join on a time range
--              would produce the same answer at quadratic cost; the window function is a single
--              ordered pass, which matters on a table with hundreds of millions of rows.
-- Pass:        zero rows.
WITH sequenced_movements AS (
    SELECT
        p.payment_id,
        p.order_id,
        p.payment_method,
        p.amount,
        p.channel,
        p.processed_at,
        LAG(p.payment_id)    OVER same_movement AS previous_payment_id,
        LAG(p.processed_at)  OVER same_movement AS previous_processed_at
    FROM payments p
    WHERE p.status = 'SETTLED'
    WINDOW same_movement AS (
        PARTITION BY p.order_id, p.payment_method, p.amount
        ORDER BY p.processed_at, p.payment_id
    )
)
SELECT
    order_id,
    payment_method,
    amount,
    channel,
    previous_payment_id,
    payment_id   AS repeated_payment_id,
    previous_processed_at,
    processed_at AS repeated_at,
    EXTRACT(EPOCH FROM (processed_at - previous_processed_at)) AS seconds_between
FROM sequenced_movements
WHERE previous_processed_at IS NOT NULL
  AND EXTRACT(EPOCH FROM (processed_at - previous_processed_at)) <= 60
ORDER BY seconds_between, order_id;


-- -------------------------------------------------------------------------------------
-- Q08. RECORDS MUTATED WITHOUT AN AUDIT TRAIL
-- -------------------------------------------------------------------------------------
-- Test case:   every payment whose updated_at moved past its created_at must have a matching
--              UPDATE entry in the audit log.
-- Risk:        a payment record changed with no trace of who changed it and when. For a company
--              handling card transactions this is an audit finding on its own, independent of
--              whether the new value happens to be correct, and it is the first thing a
--              chargeback dispute or a PCI assessment asks to see.
-- Technique:   anti-join against the audit table with the matching predicates pushed into the
--              ON clause. Putting entity_name and action in the WHERE clause instead would
--              convert the outer join into an inner join and the check would return nothing,
--              which is the most common way this exact query is written wrong.
-- Pass:        zero rows.
SELECT
    p.payment_id,
    p.order_id,
    p.external_reference,
    p.created_at,
    p.updated_at
FROM payments p
LEFT JOIN audit_log al
       ON al.entity_name = 'payments'
      AND al.entity_id   = p.payment_id
      AND al.action      = 'UPDATE'
WHERE p.updated_at IS NOT NULL
  AND p.updated_at > p.created_at
  AND al.audit_id IS NULL
ORDER BY p.updated_at;


-- -------------------------------------------------------------------------------------
-- Q09. AMOUNT INTEGRITY: ZERO, NEGATIVE, UNSUPPORTED ROUNDING AND CURRENCY MISMATCH
-- -------------------------------------------------------------------------------------
-- Test case:   every amount must be strictly positive, expressible in two decimals, and
--              denominated in the same currency as its order. Direction, not sign, is what
--              distinguishes a charge from a refund in this model.
-- Risk:        a negative charge silently becomes a refund and the customer is paid instead of
--              charged. A third decimal survives ingestion and then disappears at settlement, so
--              a fraction of a cent is lost on every movement and the finance close never ties
--              out. A currency mismatch converts at an implicit rate of one to one, which on a
--              cross-border storefront is a direct margin leak.
-- Technique:   CASE WHEN classification so each row arrives pre-triaged with its failure reason,
--              turning one query into four distinct defect reports. The LEFT JOIN keeps orphan
--              payments in scope: an orphan can also carry a corrupt amount, and losing it here
--              would leave a gap between this check and Q02.
-- Pass:        zero rows.
SELECT
    p.payment_id,
    p.order_id,
    p.external_reference,
    p.amount,
    p.currency AS payment_currency,
    o.currency AS order_currency,
    p.status,
    CASE
        WHEN p.amount = 0                                        THEN 'ZERO_AMOUNT'
        WHEN p.amount < 0                                        THEN 'NEGATIVE_AMOUNT'
        WHEN ROUND(p.amount, 2) <> p.amount                      THEN 'UNSUPPORTED_ROUNDING'
        WHEN o.currency IS NOT NULL AND o.currency <> p.currency THEN 'CURRENCY_MISMATCH'
    END AS violation
FROM payments p
LEFT JOIN orders o ON o.order_id = p.order_id
WHERE p.amount = 0
   OR p.amount < 0
   OR ROUND(p.amount, 2) <> p.amount
   OR (o.currency IS NOT NULL AND o.currency <> p.currency)
ORDER BY violation, p.payment_id;


-- -------------------------------------------------------------------------------------
-- Q10. MONTHLY SETTLEMENT TOTALS BY DIRECTION
-- -------------------------------------------------------------------------------------
-- Test case:   report, not assertion. Produces the monthly control totals that get reconciled
--              against the payment provider statement and against the figures the analytics
--              layer publishes.
-- Risk:        the storefront, the data warehouse and the payment provider each computing their
--              own totals with slightly different filters. When the three disagree at month end,
--              this query is the arbiter because it states its filters explicitly.
-- Technique:   DATE_TRUNC for monthly bucketing, conditional aggregation with CASE WHEN to split
--              charges from refunds in a single pass, and FILTER to count reversals without a
--              second query. Reversed movements are included in the totals on purpose: they are
--              part of the settlement narrative even though Q03 excludes them from order totals.
-- Pass:        totals matching the provider statement for the same period.
SELECT
    DATE_TRUNC('month', p.processed_at) AS settlement_month,
    p.currency,
    COUNT(*)                                                                AS movements,
    SUM(CASE WHEN p.direction = 'CHARGE' THEN p.amount ELSE 0 END)           AS total_charges,
    SUM(CASE WHEN p.direction = 'REFUND' THEN p.amount ELSE 0 END)           AS total_refunds,
    SUM(CASE WHEN p.direction = 'CHARGE' THEN p.amount ELSE -p.amount END)   AS net_settled,
    COUNT(*) FILTER (WHERE p.status = 'REVERSED')                           AS reversed_movements
FROM payments p
WHERE p.status IN ('SETTLED', 'REVERSED')
GROUP BY DATE_TRUNC('month', p.processed_at), p.currency
ORDER BY settlement_month, p.currency;
