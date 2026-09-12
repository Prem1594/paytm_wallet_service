package com.paytm.wallet.service;

import com.paytm.wallet.domain.Wallet;
import com.paytm.wallet.exception.WalletNotFoundException;
import com.paytm.wallet.repository.WalletRepository;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class WalletService {

    private final WalletRepository walletRepository;

    public WalletService(WalletRepository walletRepository) {
        this.walletRepository = walletRepository;
    }

    public Wallet getOrCreateWallet(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new IllegalArgumentException("User ID must not be blank");
        }
        return walletRepository.createOrGet(userId.trim());
    }

    public Wallet getWalletById(UUID id) {
        if (id == null) {
            throw new IllegalArgumentException("Wallet ID must not be null");
        }
        return walletRepository.findById(id)
                .orElseThrow(() -> new WalletNotFoundException("Wallet not found: " + id));
    }

    public Wallet getWalletByUserId(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new IllegalArgumentException("User ID must not be blank");
        }
        return walletRepository.findByUserId(userId.trim())
                .orElseThrow(() -> new WalletNotFoundException("Wallet not found for user: " + userId));
    }

    public Wallet topUp(UUID walletId, long amountPaise) {
        if (walletId == null) {
            throw new IllegalArgumentException("Wallet ID must not be null");
        }
        if (amountPaise <= 0) {
            throw new IllegalArgumentException("Top-up amount must be strictly greater than zero");
        }
        walletRepository.findById(walletId)
                .orElseThrow(() -> new WalletNotFoundException("Wallet not found: " + walletId));

        return walletRepository.topUp(walletId, amountPaise);
    }
}