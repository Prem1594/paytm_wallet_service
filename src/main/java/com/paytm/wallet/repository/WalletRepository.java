package com.paytm.wallet.repository;

import com.paytm.wallet.domain.Wallet;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public class WalletRepository {

    private final JdbcClient jdbcClient;

    public WalletRepository(JdbcClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    public Wallet createOrGet(String userId) {
        return jdbcClient.sql("""
            INSERT INTO wallets (id, user_id, balance_paise, created_at, updated_at)
            VALUES (:id, :userId, 0, NOW(), NOW())
            ON CONFLICT (user_id) DO UPDATE
            SET updated_at = wallets.updated_at
            RETURNING id, user_id, balance_paise, created_at, updated_at
            """)
            .param("id", UUID.randomUUID())
            .param("userId", userId)
            .query(Wallet.class)
            .single();
    }

    public Optional<Wallet> findById(UUID id) {
        return jdbcClient.sql("""
            SELECT id, user_id, balance_paise, created_at, updated_at
            FROM wallets
            WHERE id = :id
            """)
            .param("id", id)
            .query(Wallet.class)
            .optional();
    }

    public Optional<Wallet> findByUserId(String userId) {
        return jdbcClient.sql("""
            SELECT id, user_id, balance_paise, created_at, updated_at
            FROM wallets
            WHERE user_id = :userId
            """)
            .param("userId", userId)
            .query(Wallet.class)
            .optional();
    }

    public Wallet topUp(UUID walletId, long amountPaise) {
        return jdbcClient.sql("""
            UPDATE wallets
            SET balance_paise = balance_paise + :amount,
                updated_at = NOW()
            WHERE id = :walletId
            RETURNING id, user_id, balance_paise, created_at, updated_at
            """)
            .param("amount", amountPaise)
            .param("walletId", walletId)
            .query(Wallet.class)
            .single();
    }
}