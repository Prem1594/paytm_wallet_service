package com.paytm.wallet.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(WalletNotFoundException.class)
    public ResponseEntity<Map<String, Object>> handleWalletNotFound(WalletNotFoundException ex) {
        return buildResponse(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(TransferNotFoundException.class)
    public ResponseEntity<Map<String, Object>> handleTransferNotFound(TransferNotFoundException ex) {
        return buildResponse(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(InsufficientFundsException.class)
    public ResponseEntity<Map<String, Object>> handleInsufficientFunds(InsufficientFundsException ex) {
        return buildResponse(HttpStatus.UNPROCESSABLE_ENTITY, ex.getMessage());
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, Object>> handleConflict(IllegalStateException ex) {
        return buildResponse(HttpStatus.CONFLICT, ex.getMessage());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleBadRequest(IllegalArgumentException ex) {
        return buildResponse(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    private ResponseEntity<Map<String, Object>> buildResponse(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of(
                "status", status.value(),
                "error", message,
                "timestamp", Instant.now().toString()
        ));
    }
}