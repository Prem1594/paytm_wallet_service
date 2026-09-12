package com.paytm.wallet.controller;

import com.paytm.wallet.domain.Wallet;
import com.paytm.wallet.dto.WalletDto;
import com.paytm.wallet.service.WalletService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/wallets")
public class WalletController {

    private final WalletService walletService;

    public WalletController(WalletService walletService) {
        this.walletService = walletService;
    }

    @PostMapping
    public ResponseEntity<Wallet> createWallet(@RequestBody WalletDto.CreateRequest request) {
        Wallet wallet = walletService.getOrCreateWallet(request.userId());
        return ResponseEntity.ok(wallet);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Wallet> getWalletById(@PathVariable UUID id) {
        return ResponseEntity.ok(walletService.getWalletById(id));
    }

    @GetMapping("/users/{userId}")
    public ResponseEntity<Wallet> getWalletByUserId(@PathVariable String userId) {
        return ResponseEntity.ok(walletService.getWalletByUserId(userId));
    }

    @PostMapping("/{id}/topup")
    public ResponseEntity<Wallet> topUp(
            @PathVariable UUID id,
            @RequestBody WalletDto.TopUpRequest request
    ) {
        Wallet wallet = walletService.topUp(id, request.amountPaise());
        return ResponseEntity.ok(wallet);
    }
}