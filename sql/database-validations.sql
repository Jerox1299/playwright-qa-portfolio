-- =====================================================================================
--  database-validations.sql
--  Ten data validation checks for a transactional banking estate
--  Dialect: PostgreSQL   |   Schema and seeded defects: sql/schema-and-seed.sql
-- =====================================================================================
--
--  HOW TO READ THIS FILE
--  Each check states the test case, the risk it mitigates, the SQL technique it relies on and
--  the result that means "pass". Eight of the ten are assertions: an empty result set is a pass
--  and every returned row is a defect report ready to attach to a ticket. Two of them, Q05 and
--  Q10, are reports rather than assertions, and their headers say so explicitly.
--
--  WHY THIS MATTERS IN A TEST STRATEGY
--  The user interface can be green while the ledger is wrong. A transfer that renders correctly
--  on screen and lands twice in the core system is a defect no end-to-end test will ever see,
--  because the interface reads the same corrupted row it wrote. These checks close that gap,
--  and they are the layer that turns manual back-office reconciliation into an automatable one.
--
--  Run them against a restored production-like snapshot in a lower environment. Never against
--  production without an explicit read-only role and a signed-off change window.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- Q01. LOGICAL DUPLICATES ON A COMPOSITE TRANSACTION KEY
-- -------------------------------------------------------------------------------------
-- Test case:   the same movement must never be persisted twice for one account.
-- Risk:        a batch ingestion replay double charges the customer. The primary key hides it
--              because each copy receives its own surrogate id, so uniqueness must be asserted
--              on the BUSINESS key, not on the technical one.
-- Technique:   GROUP BY on the composite business key with HAVING COUNT(*) > 1, plus STRING_AGG
--              so the report names the offending ids instead of only counting them.
-- Pass:        zero rows.
SELECT
    t.account_id,
    t.external_reference,
    t.amount,
    t.posted_at,
    COUNT(*)                                                           AS occurrences,
    STRING_AGG(t.transaction_id::TEXT, ', ' ORDER BY t.transaction_id) AS duplicated_ids
FROM transactions t
GROUP BY t.account_id, t.external_reference, t.amount, t.posted_at
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, t.account_id;


-- -------------------------------------------------------------------------------------
-- Q02. ORPHAN TRANSACTIONS WITH NO PARENT ACCOUNT
-- -------------------------------------------------------------------------------------
-- Test case:   every movement must belong to an account that exists.
-- Risk:        broken referential integrity. Money is recorded against an account nobody owns,
--              so it is invisible to statements yet still counted in accounting totals.
-- Technique:   anti-join, expressed as LEFT JOIN plus IS NULL on the right-hand key. Preferred
--              over NOT IN because NOT IN silently returns nothing when the subquery yields a
--              NULL, which is a classic way to write a check that can never fail.
-- Pass:        zero rows.
SELECT
    t.transaction_id,
    t.account_id AS missing_account_id,
    t.external_reference,
    t.amount,
    t.currency,
    t.posted_at
FROM transactions t
LEFT JOIN accounts a ON a.account_id = t.account_id
WHERE a.account_id IS NULL
ORDER BY t.posted_at;


-- -------------------------------------------------------------------------------------
-- Q03. BALANCE RECONCILIATION: STORED BALANCE AGAINST THE MOVEMENT HISTORY
-- -------------------------------------------------------------------------------------
-- Test case:   the stored balance must equal the opening balance plus every posted movement.
-- Risk:        the single highest impact defect in retail banking. A denormalised balance column
--              drifts from its ledger after a failed rollback or a partially applied migration,
--              and the customer sees money that accounting cannot justify.
-- Technique:   aggregation inside a CTE, signed with CASE WHEN so credits add and debits
--              subtract, then compared with a tolerance. The tolerance is deliberate: exact
--              equality on decimals turns every legitimate rounding cent into a false alarm.
-- Pass:        zero rows.
WITH ledger AS (
    SELECT
        t.account_id,
        SUM(CASE WHEN t.direction = 'CREDIT' THEN t.amount ELSE -t.amount END) AS net_movement
    FROM transactions t
    WHERE t.status = 'POSTED'   -- pending and reversed movements are not part of the balance
    GROUP BY t.account_id
)
SELECT
    a.account_id,
    a.account_number,
    a.current_balance,
    a.opening_balance + COALESCE(l.net_movement, 0)                          AS expected_balance,
    a.current_balance - (a.opening_balance + COALESCE(l.net_movement, 0))    AS difference
FROM accounts a
LEFT JOIN ledger l ON l.account_id = a.account_id
WHERE ABS(a.current_balance - (a.opening_balance + COALESCE(l.net_movement, 0))) > 0.01
ORDER BY ABS(a.current_balance - (a.opening_balance + COALESCE(l.net_movement, 0))) DESC;


-- -------------------------------------------------------------------------------------
-- Q04. ACTIVE CUSTOMERS WITH NO ACCOUNT AND NO PRODUCT
-- -------------------------------------------------------------------------------------
-- Test case:   an active customer must hold at least one account or one contracted product.
-- Risk::       an onboarding flow that commits the customer record and then fails before
--              creating the account leaves a ghost customer. It inflates active customer
--              reporting and blocks the person from re-registering with the same document.
-- Technique:   two chained LEFT JOINs with IS NULL on both sides, so the check demands the
--              absence of BOTH relationships rather than either one.
-- Pass:        zero rows.
SELECT
    c.customer_id,
    c.document_number,
    c.full_name,
    c.status,
    c.created_at
FROM customers c
LEFT JOIN accounts          a ON a.customer_id = c.customer_id
LEFT JOIN customer_products p ON p.customer_id = c.customer_id
WHERE c.status = 'ACTIVE'
  AND a.account_id IS NULL
  AND p.product_id IS NULL
ORDER BY c.customer_id;


-- -------------------------------------------------------------------------------------
-- Q05. MOST RECENT TRANSACTION PER CUSTOMER, WITH DORMANCY FLAG
-- -------------------------------------------------------------------------------------
-- Test case:   report, not assertion. Returns exactly one row per customer, the latest movement.
-- Risk:        dormancy rules drive regulatory obligations and fee waivers. Getting "latest"
--              wrong by one row misclassifies the customer and the fee is charged incorrectly.
-- Technique:   ROW_NUMBER() OVER (PARTITION BY customer ORDER BY posted_at DESC) filtered to 1.
--              ROW_NUMBER is the right function here because exactly one row per customer is
--              required. DENSE_RANK would return every movement tied on the same timestamp,
--              which is the correct choice for "all top ranked" but wrong for "the latest one".
--              The tie breaker on transaction_id makes the result deterministic when two
--              movements share a timestamp, which is what keeps this query repeatable.
-- Pass:        one row per customer holding at least one posted movement.
WITH ranked_activity AS (
    SELECT
        c.customer_id,
        c.full_name,
        t.transaction_id,
        t.transaction_type,
        t.amount,
        t.posted_at,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_id
            ORDER BY t.posted_at DESC, t.transaction_id DESC
        ) AS recency_rank
    FROM customers c
    JOIN accounts     a ON a.customer_id = c.customer_id
    JOIN transactions t ON t.account_id  = a.account_id
    WHERE t.status = 'POSTED'
)
SELECT
    customer_id,
    full_name,
    transaction_id AS last_transaction_id,
    transaction_type,
    amount,
    posted_at      AS last_activity_at,
    (CURRENT_DATE - posted_at::DATE) AS days_since_last_activity,
    CASE
        WHEN (CURRENT_DATE - posted_at::DATE) > 90 THEN 'DORMANT'
        ELSE 'ACTIVE'
    END AS activity_flag
FROM ranked_activity
WHERE recency_rank = 1
ORDER BY days_since_last_activity DESC;


-- -------------------------------------------------------------------------------------
-- Q06. NEGATIVE BALANCE ON ACCOUNTS WITH NO OVERDRAFT AUTHORISATION
-- -------------------------------------------------------------------------------------
-- Test case:   an account may only go below zero when overdraft is contractually authorised.
-- Risk:        an unauthorised overdraft is real money lent without a contract. It is a
--              compliance finding, not a cosmetic bug, and it usually indicates that the
--              balance check was skipped somewhere in the payment authorisation path.
-- Technique:   predicate combining the state column with the business permission flag. The
--              query joins the customer so the report is actionable by the operations team
--              instead of being a list of anonymous identifiers.
-- Pass:        zero rows.
SELECT
    a.account_id,
    a.account_number,
    c.full_name,
    a.current_balance,
    a.overdraft_allowed,
    a.status
FROM accounts a
JOIN customers c ON c.customer_id = a.customer_id
WHERE a.current_balance < 0
  AND a.overdraft_allowed = FALSE
ORDER BY a.current_balance;


-- -------------------------------------------------------------------------------------
-- Q07. REPEATED MOVEMENTS IN A SHORT WINDOW: DOUBLE DEBIT OR REPLAY
-- -------------------------------------------------------------------------------------
-- Test case:   the same account must not receive two identical movements within sixty seconds.
-- Risk:        a retried request with no idempotency key, or a replayed message from the payment
--              queue, debits the customer twice. This one is not detectable by comparing the
--              business key, because the second copy legitimately carries a different reference.
-- Technique:   LAG() over a named window partitioned by account, type and amount, ordered by
--              time, then the elapsed seconds between neighbours. A self join on a time range
--              would produce the same answer at quadratic cost; the window function is a single
--              ordered pass, which matters on a table with hundreds of millions of rows.
-- Pass:        zero rows.
WITH sequenced_movements AS (
    SELECT
        t.transaction_id,
        t.account_id,
        t.transaction_type,
        t.amount,
        t.channel,
        t.posted_at,
        LAG(t.transaction_id) OVER same_movement AS previous_transaction_id,
        LAG(t.posted_at)      OVER same_movement AS previous_posted_at
    FROM transactions t
    WHERE t.status = 'POSTED'
    WINDOW same_movement AS (
        PARTITION BY t.account_id, t.transaction_type, t.amount
        ORDER BY t.posted_at, t.transaction_id
    )
)
SELECT
    account_id,
    transaction_type,
    amount,
    channel,
    previous_transaction_id,
    transaction_id AS repeated_transaction_id,
    previous_posted_at,
    posted_at      AS repeated_at,
    EXTRACT(EPOCH FROM (posted_at - previous_posted_at)) AS seconds_between
FROM sequenced_movements
WHERE previous_posted_at IS NOT NULL
  AND EXTRACT(EPOCH FROM (posted_at - previous_posted_at)) <= 60
ORDER BY seconds_between, account_id;


-- -------------------------------------------------------------------------------------
-- Q08. RECORDS MUTATED WITHOUT AN AUDIT TRAIL
-- -------------------------------------------------------------------------------------
-- Test case:   every transaction whose updated_at moved past its created_at must have a
--              matching UPDATE entry in the audit log.
-- Risk::       a financial record changed with no trace of who changed it and when. In a
--              regulated environment this is an audit finding on its own, independent of
--              whether the new value happens to be correct.
-- Technique:   anti-join against the audit table with the matching predicates pushed into the
--              ON clause. Putting entity_name and action in the WHERE clause instead would
--              convert the outer join into an inner join and the check would return nothing,
--              which is the most common way this exact query is written wrong.
-- Pass:        zero rows.
SELECT
    t.transaction_id,
    t.account_id,
    t.external_reference,
    t.created_at,
    t.updated_at
FROM transactions t
LEFT JOIN audit_log al
       ON al.entity_name = 'transactions'
      AND al.entity_id   = t.transaction_id
      AND al.action      = 'UPDATE'
WHERE t.updated_at IS NOT NULL
  AND t.updated_at > t.created_at
  AND al.audit_id IS NULL
ORDER BY t.updated_at;


-- -------------------------------------------------------------------------------------
-- Q09. AMOUNT INTEGRITY: ZERO, NEGATIVE, UNSUPPORTED ROUNDING AND CURRENCY MISMATCH
-- -------------------------------------------------------------------------------------
-- Test case:   every amount must be strictly positive, expressible in two decimals, and
--              denominated in the same currency as its account. Direction, not sign, is what
--              distinguishes a debit from a credit in this model.
-- Risk:        a negative debit silently becomes a credit and the customer is paid instead of
--              charged. A third decimal survives ingestion and then disappears on settlement,
--              so a fraction of a cent is lost on every movement. A currency mismatch converts
--              at an implicit rate of one to one.
-- Technique:   CASE WHEN classification so each row arrives pre-triaged with its failure reason,
--              turning one query into four distinct defect reports. The LEFT JOIN keeps orphan
--              transactions in scope: an orphan can also carry a corrupt amount, and losing it
--              here would leave a gap between this check and Q02.
-- Pass:        zero rows.
SELECT
    t.transaction_id,
    t.account_id,
    t.external_reference,
    t.amount,
    t.currency     AS transaction_currency,
    a.currency     AS account_currency,
    t.status,
    CASE
        WHEN t.amount = 0                                        THEN 'ZERO_AMOUNT'
        WHEN t.amount < 0                                        THEN 'NEGATIVE_AMOUNT'
        WHEN ROUND(t.amount, 2) <> t.amount                      THEN 'UNSUPPORTED_ROUNDING'
        WHEN a.currency IS NOT NULL AND a.currency <> t.currency THEN 'CURRENCY_MISMATCH'
    END AS violation
FROM transactions t
LEFT JOIN accounts a ON a.account_id = t.account_id
WHERE t.amount = 0
   OR t.amount < 0
   OR ROUND(t.amount, 2) <> t.amount
   OR (a.currency IS NOT NULL AND a.currency <> t.currency)
ORDER BY violation, t.transaction_id;


-- -------------------------------------------------------------------------------------
-- Q10. MONTHLY ACCOUNTING TOTALS BY DIRECTION
-- -------------------------------------------------------------------------------------
-- Test case:   report, not assertion. Produces the monthly control totals that get reconciled
--              against the general ledger and against the figures the reporting layer publishes.
-- Risk:        the interface, the data warehouse and accounting each computing their own totals
--              with slightly different filters. When the three disagree, this query is the
--              arbiter because it states its filters explicitly.
-- Technique:   DATE_TRUNC for monthly bucketing, conditional aggregation with CASE WHEN to split
--              credits from debits in a single pass, and FILTER to count reversals without a
--              second query. Reversed movements are included in the totals on purpose: they are
--              part of the accounting narrative even though Q03 excludes them from balances.
-- Pass:        totals matching the ledger for the same period.
SELECT
    DATE_TRUNC('month', t.posted_at) AS accounting_month,
    t.currency,
    COUNT(*)                                                                AS movements,
    SUM(CASE WHEN t.direction = 'CREDIT' THEN t.amount ELSE 0 END)           AS total_credits,
    SUM(CASE WHEN t.direction = 'DEBIT'  THEN t.amount ELSE 0 END)           AS total_debits,
    SUM(CASE WHEN t.direction = 'CREDIT' THEN t.amount ELSE -t.amount END)   AS net_movement,
    COUNT(*) FILTER (WHERE t.status = 'REVERSED')                            AS reversed_movements
FROM transactions t
WHERE t.status IN ('POSTED', 'REVERSED')
GROUP BY DATE_TRUNC('month', t.posted_at), t.currency
ORDER BY accounting_month, t.currency;
