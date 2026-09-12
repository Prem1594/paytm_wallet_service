package com.paytm.wallet.dto;

import com.fasterxml.jackson.annotation.JsonAlias;

public class WalletDto {

    public record CreateRequest(
        @JsonAlias({"user_id", "userId"}) String userId
    ) {}

    public record TopUpRequest(
        @JsonAlias({"amount_paise", "amountPaise"}) long amountPaise
    ) {}
}