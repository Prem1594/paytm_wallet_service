package com.paytm.wallet.domain;

import java.time.Instant;
import java.util.UUID;

public record Transfer(
    UUID id,
    UUID fromWalletId,
    UUID toWalletId,
    long amountPaise,
    String idempotencyKey,
    String requestHash,
    String status,
    String reason,
    Instant createdAt
) {}