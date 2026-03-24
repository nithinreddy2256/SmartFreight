package com.smartfreight.invoice.controller.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public record ReceiveInvoiceRequest(

        @NotBlank String invoiceNumber,
        @NotBlank String carrierId,
        String carrierName,
        String shipmentReferenceNumber,
        @NotNull LocalDate invoiceDate,
        @NotNull @Positive BigDecimal invoicedAmount,
        String currency,
        /** S3 key of the uploaded invoice PDF (from document-service presigned upload). */
        String documentKey,
        String glCode,
        List<LineItemRequest> lineItems
) {
    public record LineItemRequest(
            @NotBlank String description,
            String chargeType,
            BigDecimal quantity,
            BigDecimal unitPrice,
            @NotNull @Positive BigDecimal totalAmount,
            String glCode
    ) {}
}
