package com.paytm.wallet.util;

import com.paytm.wallet.dto.TransferDto;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

@Component
public class RequestHasher {

    public String computeHash(TransferDto.Request request) {
        if (request == null) {
            throw new IllegalArgumentException("Transfer request must not be null");
        }

        // Canonical deterministic representation: source:target:amount
        String canonicalPayload = String.format("%s:%s:%d",
                request.sourceWalletId(),
                request.targetWalletId(),
                request.amountPaise()
        );

        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashBytes = digest.digest(canonicalPayload.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hashBytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 algorithm not available in current JVM runtime", e);
        }
    }
}