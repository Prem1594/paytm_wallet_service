package com.paytm.wallet.controller;

import com.paytm.wallet.dto.TransferDto;
import com.paytm.wallet.service.TransferService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/transfers")
public class TransferController {

    private final TransferService transferService;

    public TransferController(TransferService transferService) {
        this.transferService = transferService;
    }

    @PostMapping
    public ResponseEntity<TransferDto.Response> createTransfer(
            @RequestHeader(value = "Idempotency-Key", required = false) String headerKey,
            @RequestBody TransferDto.Request request
    ) {
        String effectiveKey = (headerKey != null && !headerKey.isBlank())
                ? headerKey
                : request.idempotencyKey();

        TransferDto.Response response = transferService.executeTransfer(request, effectiveKey);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<TransferDto.Response> getTransferById(@PathVariable UUID id) {
        return ResponseEntity.ok(transferService.getTransferById(id));
    }
}