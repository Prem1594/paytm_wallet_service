package com.paytm.wallet.repository;

import com.paytm.wallet.domain.Transfer;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public class TransferRepository {

    private final JdbcClient jdbcClient;

    public TransferRepository(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    public void acquireIdempotencyLock(String idempotencyKey) {
        jdbcClient.sql("SELECT pg_advisory_xact_lock(hashtext(:key))")
                .param("key", idempotencyKey)
                .query()
                .singleRow();
    }

    public Optional<Transfer> findById(UUID id) {
        return jdbcClient.sql("""
            SELECT id, from_wallet_id, to_wallet_id, amount_paise, idempotency_key, request_hash, status, reason, created_at
            FROM transfers
            WHERE id = :id
            """)
            .param("id", id)
            .query(Transfer.class)
            .optional();
    }

    public Optional<Transfer> findByIdempotencyKey(String idempotencyKey) {
        return jdbcClient.sql("""
            SELECT id, from_wallet_id, to_wallet_id, amount_paise, idempotency_key, request_hash, status, reason, created_at
            FROM transfers
            WHERE idempotency_key = :idempotencyKey
            """)
            .param("idempotencyKey", idempotencyKey)
            .query(Transfer.class)
            .optional();
    }

    public void acquireWalletLock(UUID walletId) {
        jdbcClient.sql("""
            SELECT id
            FROM wallets
            WHERE id = :walletId
            FOR UPDATE
            """)
            .param("walletId", walletId)
            .query()
            .singleRow();
    }

    public boolean debit(UUID walletId, long amountPaise) {
        int rowsUpdated = jdbcClient.sql("""
            UPDATE wallets
            SET balance_paise = balance_paise - :amount,
                updated_at = NOW()
            WHERE id = :walletId AND balance_paise >= :amount
            """)
            .param("amount", amountPaise)
            .param("walletId", walletId)
            .update();

        return rowsUpdated > 0;
    }

    public void credit(UUID walletId, long amountPaise) {
        jdbcClient.sql("""
            UPDATE wallets
            SET balance_paise = balance_paise + :amount,
                updated_at = NOW()
            WHERE id = :walletId
            """)
            .param("amount", amountPaise)
            .param("walletId", walletId)
            .update();
    }

    public Transfer recordTransfer(
            UUID id,
            UUID fromWalletId,
            UUID toWalletId,
            long amountPaise,
            String idempotencyKey,
            String requestHash,
            String status,
            String reason
    ) {
        return jdbcClient.sql("""
            INSERT INTO transfers (id, from_wallet_id, to_wallet_id, amount_paise, idempotency_key, request_hash, status, reason, created_at)
            VALUES (:id, :fromWalletId, :toWalletId, :amountPaise, :idempotencyKey, :requestHash, :status, :reason, NOW())
            RETURNING id, from_wallet_id, to_wallet_id, amount_paise, idempotency_key, request_hash, status, reason, created_at
            """)
            .param("id", id)
            .param("fromWalletId", fromWalletId)
            .param("toWalletId", toWalletId)
            .param("amountPaise", amountPaise)
            .param("idempotencyKey", idempotencyKey)
            .param("requestHash", requestHash)
            .param("status", status)
            .param("reason", reason)
            .query(Transfer.class)
            .single();
    }
}