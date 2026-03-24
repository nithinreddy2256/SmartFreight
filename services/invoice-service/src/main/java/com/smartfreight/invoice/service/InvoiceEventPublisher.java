package com.smartfreight.invoice.service;

import com.smartfreight.aws.messaging.SnsPublisher;
import com.smartfreight.common.events.InvoiceApprovedEvent;
import com.smartfreight.common.events.InvoiceDisputedEvent;
import com.smartfreight.invoice.domain.Invoice;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

@Slf4j
@Component
@RequiredArgsConstructor
public class InvoiceEventPublisher {

    private final SnsPublisher snsPublisher;

    @Value("${aws.sns.invoice-events-topic-arn}")
    private String invoiceEventsTopicArn;

    public void publishInvoiceApproved(Invoice invoice) {
        var event = InvoiceApprovedEvent.builder()
                .invoiceId(invoice.getId())
                .invoiceNumber(invoice.getInvoiceNumber())
                .carrierId(invoice.getCarrierId())
                .carrierName(invoice.getCarrierName())
                .shipmentId(invoice.getShipmentId())
                .shipmentReferenceNumber(invoice.getShipmentReferenceNumber())
                .approvedAmount(invoice.getApprovedAmount())
                .currency(invoice.getCurrency())
                .glCode(invoice.getGlCode())
                .invoiceDate(invoice.getInvoiceDate())
                .paymentDueDate(invoice.getPaymentDueDate())
                .autoApproved(invoice.isAutoApproved())
                .approvedAt(invoice.getApprovedAt())
                .build();
        snsPublisher.publish(invoiceEventsTopicArn, event, "InvoiceApprovedEvent");
        log.info("Published InvoiceApprovedEvent. invoiceId={}", invoice.getId());
    }

    public void publishInvoiceDisputed(Invoice invoice) {
        BigDecimal discrepancy = (invoice.getInvoicedAmount() != null && invoice.getExpectedAmount() != null)
                ? invoice.getInvoicedAmount().subtract(invoice.getExpectedAmount()) : null;
        var event = InvoiceDisputedEvent.builder()
                .invoiceId(invoice.getId())
                .invoiceNumber(invoice.getInvoiceNumber())
                .carrierId(invoice.getCarrierId())
                .carrierName(invoice.getCarrierName())
                .shipmentId(invoice.getShipmentId())
                .shipmentReferenceNumber(invoice.getShipmentReferenceNumber())
                .invoicedAmount(invoice.getInvoicedAmount())
                .expectedAmount(invoice.getExpectedAmount())
                .discrepancyAmount(discrepancy)
                .discrepancyPercentage(invoice.discrepancyPercentage())
                .disputeReason(invoice.getDisputeReason())
                .disputeDescription(invoice.getDisputeDescription())
                .build();
        snsPublisher.publish(invoiceEventsTopicArn, event, "InvoiceDisputedEvent");
        log.info("Published InvoiceDisputedEvent. invoiceId={} reason={}", invoice.getId(), invoice.getDisputeReason());
    }
}
