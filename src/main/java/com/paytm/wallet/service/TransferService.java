package com.paytm.wallet.service;

import com.paytm.wallet.domain.Transfer;
import com.paytm.wallet.dto.TransferDto;
import com.paytm.wallet.exception.InsufficientFundsException;
import com.paytm.wallet.exception.TransferNotFoundException;
import com.paytm.wallet.exception.WalletNotFoundException;
import com.paytm.wallet.repository.TransferRepository;
import com.paytm.wallet.repository.WalletRepository;
import com.paytm.wallet.util.RequestHasher;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

@Service
public class TransferService {

    private static final Logger log = LoggerFactory.getLogger(TransferService.class);

    private final TransferRepository transferRepository;
    private final WalletRepository walletRepository;
    private final RequestHasher requestHasher;

    private final Counter transfersCreatedCounter;
    private final Counter transfersDeclinedCounter;
    private final Counter idempotentReplaysCounter;

    public TransferService(
            TransferRepository transferRepository,
            WalletRepository walletRepository,
            RequestHasher requestHasher,
            MeterRegistry meterRegistry
    ) {
        this.transferRepository = transferRepository;
        this.walletRepository = walletRepository;
        this.requestHasher = requestHasher;

        this.transfersCreatedCounter = Counter.builder("transfers_created")
                .description("Total number of successful transfers created")
                .register(meterRegistry);

        this.transfersDeclinedCounter = Counter.builder("transfers_declined_insufficient_funds")
                .description("Total number of transfers declined due to insufficient funds")
                .register(meterRegistry);

        this.idempotentReplaysCounter = Counter.builder("idempotent_replays")
                .description("Total number of idempotent replay hits served")
                .register(meterRegistry);
    }

    public TransferDto.Response getTransferById(UUID id) {
        if (id == null) {
            throw new IllegalArgumentException("Transfer ID must not be null");
        }
        Transfer transfer = transferRepository.findById(id)
                .orElseThrow(() -> new TransferNotFoundException("Transfer not found: " + id));

        return new TransferDto.Response(
                transfer.id(),
                transfer.fromWalletId(),
                transfer.toWalletId(),
                transfer.amountPaise(),
                transfer.status(),
                transfer.reason(),
                transfer.createdAt()
        );
    }

    @Transactional(noRollbackFor = InsufficientFundsException.class)
    public TransferDto.Response executeTransfer(TransferDto.Request request, String idempotencyKey) {
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            throw new IllegalArgumentException("Idempotency key is required");
        }
        if (request.sourceWalletId() == null || request.targetWalletId() == null) {
            throw new IllegalArgumentException("Source and target wallet IDs must not be null");
        }
        if (request.sourceWalletId().equals(request.targetWalletId())) {
            throw new IllegalArgumentException("Cannot transfer funds to the same wallet");
        }
        if (request.amountPaise() == null || request.amountPaise() <= 0) {
            throw new IllegalArgumentException("Transfer amount must be strictly greater than zero");
        }

        String sanitizedKey = idempotencyKey.trim();

        // Prevent TOCTOU storm via transaction-level advisory lock
        transferRepository.acquireIdempotencyLock(sanitizedKey);

        String currentPayloadHash = requestHasher.computeHash(request);

        // 1. Idempotency replay check
        Optional<Transfer> existingTransfer = transferRepository.findByIdempotencyKey(sanitizedKey);
        if (existingTransfer.isPresent()) {
            Transfer transfer = existingTransfer.get();

            if (!transfer.requestHash().equals(currentPayloadHash)) {
                throw new IllegalStateException("Idempotency key reuse with mismatched transfer parameters");
            }

            idempotentReplaysCounter.increment();
            log.info("idempotent replay hit: key={}, transferId={}, status={}", sanitizedKey, transfer.id(), transfer.status());

            if ("DECLINED".equals(transfer.status())) {
                throw new InsufficientFundsException(
                    transfer.reason() != null ? transfer.reason() : "Source wallet has insufficient balance for transfer"
                );
            }

            return new TransferDto.Response(
                    transfer.id(),
                    transfer.fromWalletId(),
                    transfer.toWalletId(),
                    transfer.amountPaise(),
                    transfer.status(),
                    transfer.reason(),
                    transfer.createdAt()
            );
        }

        // 2. Validate wallets
        walletRepository.findById(request.sourceWalletId())
                .orElseThrow(() -> new WalletNotFoundException("Source wallet not found: " + request.sourceWalletId()));
        walletRepository.findById(request.targetWalletId())
                .orElseThrow(() -> new WalletNotFoundException("Target wallet not found: " + request.targetWalletId()));

        // 3. Canonical lock ordering
        UUID firstLock = request.sourceWalletId().compareTo(request.targetWalletId()) < 0 
                ? request.sourceWalletId() 
                : request.targetWalletId();
        UUID secondLock = request.sourceWalletId().compareTo(request.targetWalletId()) < 0 
                ? request.targetWalletId() 
                : request.sourceWalletId();

        transferRepository.acquireWalletLock(firstLock);
        transferRepository.acquireWalletLock(secondLock);

        // 4. Atomic debit guard
        boolean debited = transferRepository.debit(request.sourceWalletId(), request.amountPaise());
        if (!debited) {
            transfersDeclinedCounter.increment();
            log.warn("transfer declined: from={} to={} amount={} reason=INSUFFICIENT_FUNDS",
                    request.sourceWalletId(), request.targetWalletId(), request.amountPaise());

            transferRepository.recordTransfer(
                    UUID.randomUUID(),
                    request.sourceWalletId(),
                    request.targetWalletId(),
                    request.amountPaise(),
                    sanitizedKey,
                    currentPayloadHash,
                    "DECLINED",
                    "Source wallet has insufficient balance for transfer"
            );
            throw new InsufficientFundsException("Source wallet has insufficient balance for transfer");
        }

        log.info("wallet debited: walletId={} amount={}", request.sourceWalletId(), request.amountPaise());

        // 5. Credit target
        transferRepository.credit(request.targetWalletId(), request.amountPaise());
        log.info("wallet credited: walletId={} amount={}", request.targetWalletId(), request.amountPaise());

        // 6. Record completed transfer
        Transfer recorded = transferRepository.recordTransfer(
                UUID.randomUUID(),
                request.sourceWalletId(),
                request.targetWalletId(),
                request.amountPaise(),
                sanitizedKey,
                currentPayloadHash,
                "COMPLETED",
                null
        );

        transfersCreatedCounter.increment();
        log.info("transfer created: id={} from={} to={} amount={}",
                recorded.id(), recorded.fromWalletId(), recorded.toWalletId(), recorded.amountPaise());

        return new TransferDto.Response(
                recorded.id(),
                recorded.fromWalletId(),
                recorded.toWalletId(),
                recorded.amountPaise(),
                recorded.status(),
                recorded.reason(),
                recorded.createdAt()
        );
    }
}