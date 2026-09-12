package com.paytm.wallet.dto;

import com.fasterxml.jackson.annotation.JsonAlias;

import java.time.Instant;
import java.util.UUID;

public class TransferDto {

    public record Request(
        @JsonAlias({"from", "source_wallet_id"}) UUID sourceWalletId,
        @JsonAlias({"to", "target_wallet_id"}) UUID targetWalletId,
        @JsonAlias({"amount_paise"}) Long amountPaise,
        @JsonAlias({"idempotency_key"}) String idempotencyKey
    ) {}

    public record Response(
        UUID transferId,
        UUID sourceWalletId,
        UUID targetWalletId,
        long amountPaise,
        String status,
        String reason,
        Instant timestamp
    ) {
        public Response(UUID transferId, UUID sourceWalletId, UUID targetWalletId, long amountPaise, String status, Instant timestamp) {
            this(transferId, sourceWalletId, targetWalletId, amountPaise, status, null, timestamp);
        }
    }
}