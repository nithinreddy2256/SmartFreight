package com.smartfreight.invoice.service;

import com.smartfreight.common.events.InvoiceApprovedEvent;
import com.smartfreight.common.events.InvoiceDisputedEvent;
import com.smartfreight.invoice.controller.dto.ReceiveInvoiceRequest;
import com.smartfreight.invoice.domain.Invoice;
import com.smartfreight.invoice.domain.InvoiceLineItem;
import com.smartfreight.invoice.domain.InvoiceStatus;
import com.smartfreight.invoice.repository.InvoiceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.NoSuchElementException;

@Slf4j
@Service
@RequiredArgsConstructor
public class InvoiceService {

    private final InvoiceRepository invoiceRepository;
    private final ThreeWayMatchService threeWayMatchService;
    private final InvoiceEventPublisher eventPublisher;

    @Value("${invoice.payment.default-terms-days:30}")
    private int defaultPaymentTermsDays;

    @Transactional
    public Invoice receiveInvoice(ReceiveInvoiceRequest req) {
        if (invoiceRepository.findByInvoiceNumber(req.invoiceNumber()).isPresent()) {
            throw new IllegalArgumentException("Duplicate invoice number: " + req.invoiceNumber());
        }

        var invoice = Invoice.builder()
                .invoiceNumber(req.invoiceNumber())
                .carrierId(req.carrierId())
                .carrierName(req.carrierName())
                .shipmentReferenceNumber(req.shipmentReferenceNumber())
                .invoiceDate(req.invoiceDate())
                .invoicedAmount(req.invoicedAmount())
                .currency(req.currency() != null ? req.currency() : "USD")
                .glCode(req.glCode())
                .documentKey(req.documentKey())
                .status(InvoiceStatus.RECEIVED)
                .paymentDueDate(req.invoiceDate().plusDays(defaultPaymentTermsDays))
                .build();

        if (req.lineItems() != null) {
            req.lineItems().forEach(li -> {
                var lineItem = InvoiceLineItem.builder()
                        .invoice(invoice)
                        .description(li.description())
                        .chargeType(li.chargeType())
                        .quantity(li.quantity())
                        .unitPrice(li.unitPrice())
                        .totalAmount(li.totalAmount())
                        .glCode(li.glCode())
                        .build();
                invoice.getLineItems().add(lineItem);
            });
        }

        var saved = invoiceRepository.save(invoice);
        log.info("Invoice received. invoiceId={} invoiceNumber={}", saved.getId(), saved.getInvoiceNumber());
        return saved;
    }

    @Transactional
    public Invoice runThreeWayMatch(String invoiceId, String shipmentId) {
        var invoice = getById(invoiceId);
        invoice.setShipmentId(shipmentId);
        invoice.setStatus(InvoiceStatus.MATCHING);

        var result = threeWayMatchService.match(invoice, shipmentId != null);

        var saved = invoiceRepository.save(invoice);

        if (result.outcome() == ThreeWayMatchService.MatchOutcome.APPROVED) {
            invoice.setApprovedAt(Instant.now());
            eventPublisher.publishInvoiceApproved(saved);
            log.info("Invoice approved after 3-way match. invoiceId={}", invoiceId);
        } else {
            eventPublisher.publishInvoiceDisputed(saved);
            log.warn("Invoice disputed after 3-way match. invoiceId={} reason={}", invoiceId, result.reason());
        }

        return saved;
    }

    @Transactional
    public Invoice manualApprove(String invoiceId, String approvedBy) {
        var invoice = getById(invoiceId);
        invoice.setStatus(InvoiceStatus.APPROVED);
        invoice.setApprovedAt(Instant.now());
        invoice.setApprovedBy(approvedBy);
        invoice.setApprovedAmount(invoice.getInvoicedAmount());
        var saved = invoiceRepository.save(invoice);
        eventPublisher.publishInvoiceApproved(saved);
        log.info("Invoice manually approved. invoiceId={} by={}", invoiceId, approvedBy);
        return saved;
    }

    @Transactional
    public Invoice markPaid(String invoiceId) {
        var invoice = getById(invoiceId);
        invoice.setStatus(InvoiceStatus.PAID);
        invoice.setPaidAt(Instant.now());
        return invoiceRepository.save(invoice);
    }

    public Invoice getById(String invoiceId) {
        return invoiceRepository.findById(invoiceId)
                .orElseThrow(() -> new NoSuchElementException("Invoice not found: " + invoiceId));
    }

    public Page<Invoice> listAll(Pageable pageable) {
        return invoiceRepository.findAll(pageable);
    }

    public Page<Invoice> listByStatus(InvoiceStatus status, Pageable pageable) {
        return invoiceRepository.findByStatus(status, pageable);
    }

    public Page<Invoice> listByCarrier(String carrierId, Pageable pageable) {
        return invoiceRepository.findByCarrierId(carrierId, pageable);
    }

    public List<Invoice> getByShipmentId(String shipmentId) {
        return invoiceRepository.findByShipmentId(shipmentId);
    }

    public List<Invoice> getOverdueInvoices() {
        return invoiceRepository.findOverdueInvoices(LocalDate.now());
    }
}
