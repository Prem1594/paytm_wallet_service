CREATE TABLE wallets(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(64) UNIQUE NOT NULL,
    balance_paise BIGINT NOT NULL DEFAULT 0 CHECK (balance_paise >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallets_user_id ON wallets(user_id);

CREATE TABLE transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key VARCHAR(128) UNIQUE NOT NULL,
    request_hash CHAR(64) NOT NULL,
    from_wallet_id UUID NOT NULL REFERENCES wallets(id),
    to_wallet_id UUID NOT NULL REFERENCES wallets(id),
    amount_paise BIGINT NOT NULL CHECK (amount_paise > 0),
    status VARCHAR(20) NOT NULL CHECK (status IN ('COMPLETED', 'DECLINED')),
    reason VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transfers_idempotency ON transfers(idempotency_key);