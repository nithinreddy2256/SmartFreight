package com.smartfreight.invoice.controller.dto;

import com.smartfreight.invoice.domain.Invoice;
import com.smartfreight.invoice.domain.InvoiceLineItem;
import com.smartfreight.invoice.domain.InvoiceStatus;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public record InvoiceDto(
        String id,
        String invoiceNumber,
        String carrierId,
        String carrierName,
        String shipmentId,
        String shipmentReferenceNumber,
        LocalDate invoiceDate,
        BigDecimal invoicedAmount,
        BigDecimal expectedAmount,
        BigDecimal approvedAmount,
        String currency,
        String glCode,
        InvoiceStatus status,
        String documentKey,
        String disputeReason,
        String disputeDescription,
        LocalDate paymentDueDate,
        boolean autoApproved,
        Instant approvedAt,
        String approvedBy,
        Instant createdAt,
        List<LineItemDto> lineItems
) {
    public record LineItemDto(
            String id,
            String description,
            String chargeType,
            BigDecimal quantity,
            BigDecimal unitPrice,
            BigDecimal totalAmount,
            String glCode
    ) {}

    public static InvoiceDto from(Invoice i) {
        var lineItems = i.getLineItems().stream()
                .map(li -> new LineItemDto(
                        li.getId(), li.getDescription(), li.getChargeType(),
                        li.getQuantity(), li.getUnitPrice(), li.getTotalAmount(), li.getGlCode()))
                .toList();
        return new InvoiceDto(
                i.getId(), i.getInvoiceNumber(), i.getCarrierId(), i.getCarrierName(),
                i.getShipmentId(), i.getShipmentReferenceNumber(), i.getInvoiceDate(),
                i.getInvoicedAmount(), i.getExpectedAmount(), i.getApprovedAmount(),
                i.getCurrency(), i.getGlCode(), i.getStatus(), i.getDocumentKey(),
                i.getDisputeReason(), i.getDisputeDescription(), i.getPaymentDueDate(),
                i.isAutoApproved(), i.getApprovedAt(), i.getApprovedBy(), i.getCreatedAt(),
                lineItems);
    }
}
