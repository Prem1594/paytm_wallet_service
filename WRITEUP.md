# Paytm Wallet & P2P Transfer Service — Architectural Write-Up

## 1. Data Model
All monetary values are modeled exclusively as 64-bit integer paise (`BIGINT`), strictly eliminating floating-point rounding errors.

* **`wallets`**: `id` (UUID, PK), `user_id` (VARCHAR, UNIQUE), `balance_paise` (BIGINT, CHECK >= 0), `created_at` (TIMESTAMPTZ), `updated_at` (TIMESTAMPTZ).
* **`transfers`**: `id` (UUID, PK), `from_wallet_id` (UUID, FK), `to_wallet_id` (UUID, FK), `amount_paise` (BIGINT, CHECK > 0), `idempotency_key` (VARCHAR, UNIQUE), `request_hash` (CHAR 64), `status` (VARCHAR CHECK IN ('COMPLETED', 'DECLINED')), `reason` (VARCHAR), `created_at` (TIMESTAMPTZ).

---

## 2. Simplest-Correct Mechanism for Conservation & No-Overdraft
To guarantee balance conservation and prevent overdrafts under high concurrency, we employ a **canonical row-lock acquisition strategy combined with an in-database atomic conditional debit**:

1. **Deadlock Prevention (Canonical Lock Ordering):** When transferring between Wallet A and Wallet B, transactions acquire row-level locks (`SELECT id FROM wallets WHERE id = :id FOR UPDATE`) sorted lexicographically by UUID (`min(id)` then `max(id)`). This eliminates circular wait conditions when concurrent transfers run in opposite directions ($A \rightarrow B$ and $B \rightarrow A$).
2. **Atomic Conditional Debit:** Balances are decremented via `UPDATE wallets SET balance_paise = balance_paise - :amount WHERE id = :id AND balance_paise >= :amount`. If `rows_affected == 0`, the transaction records a `DECLINED` entry with reason `INSUFFICIENT_FUNDS` and returns HTTP 422, guaranteeing zero partial writes and zero negative balances.

### Rejected Alternatives
* **Serializable Isolation:** Rejected due to high transaction retry storms and serialization aborts under high-contention bursts, shifting coordination overhead into application retry loops.
* **Application-Level Locks (`synchronized` / `ReentrantLock`):** Rejected because in-memory concurrency controls break instantly across multi-instance horizontally scaled deployments.
* **Distributed Locking (Redis/Redlock):** Rejected as an unnecessary operational dependency. It introduces split-brain risk under network partitions and clock skew vulnerabilities, whereas PostgreSQL row-level locks provide ACID safety directly at the datastore level.

---

## 3. Where Idempotency Lives
Idempotency enforcement is committed **inside the same database transaction** as the balance updates:
* **Race Protection:** At the start of the transaction, a PostgreSQL transaction-scoped advisory lock (`pg_advisory_xact_lock(hashtext(:key))`) serializes concurrent duplicate requests sharing the same key, eliminating Time-of-Check to Time-of-Use (TOCTOU) races.
* **Tamper Detection:** Every request payload (`sourceWalletId`, `targetWalletId`, `amountPaise`) is hashed using SHA-256 (`request_hash`). If an existing `idempotency_key` is replayed with mismatched payload parameters, the system returns `HTTP 409 Conflict`.
* **State Persistence:** Successful and declined transactions are both permanently recorded in `transfers`. Identical retries bypass ledger movements and replay the cached state.

---

## 4. Consistency vs. Availability (CAP Trade-off)
For a financial ledger, **Consistency (Linearizability) is prioritized over Availability (CP system)**. 
* We explicitly forfeit eventual consistency: balance reads and debits are strictly serialized at the row level. 
* If a wallet experiences high contention or temporary partition, incoming requests for that wallet wait or fail cleanly rather than accepting an unverified debit that could permit double-spending.

---

## 5. AI Directed vs. Decided Disclosure
* **Human Directed:** Core architectural design, canonical UUID lock ordering for deadlock prevention, database schema constraints (`CHECK >= 0`, integer paise), transaction boundary isolation (`noRollbackFor`), advisory lock placement, and the multi-stage non-root Docker build.
* **AI Decided / Typed:** Boilerplate Spring Boot `JdbcClient` queries, Logback JSON encoder configuration, Micrometer Prometheus metrics integration, and Bash script orchestration for the burst probes.

---

## 6. Infrastructure & Free-Tier Cost Note
* **Hosting:** Render Web Service (Free Tier, 0.1 vCPU, 512MB RAM) / Fly.io.
* **Database:** Managed PostgreSQL (Render Free Tier / Neon Free Tier).
* **Total Cost:** ₹0.00 (Zero card required).