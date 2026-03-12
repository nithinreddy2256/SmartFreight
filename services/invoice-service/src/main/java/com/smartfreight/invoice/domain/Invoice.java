package com.smartfreight.invoice.domain;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Freight invoice aggregate root.
 *
 * <p>Lifecycle: RECEIVED → OCR_PENDING → OCR_COMPLETE → MATCHING → (APPROVED | DISPUTED) → PAID
 */
@Entity
@Table(name = "invoices", indexes = {
        @Index(name = "idx_invoices_carrier_id", columnList = "carrier_id"),
        @Index(name = "idx_invoices_shipment_id", columnList = "shipment_id"),
        @Index(name = "idx_invoices_status", columnList = "status"),
        @Index(name = "idx_invoices_invoice_number", columnList = "invoice_number")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Invoice {

    @Id
    @Column(name = "id", updatable = false, nullable = false, length = 36)
    @Builder.Default
    private String id = UUID.randomUUID().toString();

    @Column(name = "invoice_number", unique = true, nullable = false, length = 100)
    private String invoiceNumber;

    @Column(name = "carrier_id", nullable = false, length = 36)
    private String carrierId;

    @Column(name = "carrier_name", length = 200)
    private String carrierName;

    @Column(name = "shipment_id", length = 36)
    private String shipmentId;

    @Column(name = "shipment_reference_number", length = 20)
    private String shipmentReferenceNumber;

    @Column(name = "invoice_date")
    private LocalDate invoiceDate;

    @Column(name = "invoiced_amount", precision = 12, scale = 2)
    private BigDecimal invoicedAmount;

    @Column(name = "expected_amount", precision = 12, scale = 2)
    private BigDecimal expectedAmount;

    @Column(name = "approved_amount", precision = 12, scale = 2)
    private BigDecimal approvedAmount;

    @Column(name = "currency", length = 3)
    @Builder.Default
    private String currency = "USD";

    @Column(name = "gl_code", length = 20)
    private String glCode;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 30)
    @Builder.Default
    private InvoiceStatus status = InvoiceStatus.RECEIVED;

    /** S3 object key of the invoice PDF document. */
    @Column(name = "document_key", length = 500)
    private String documentKey;

    /** Amazon Textract async job ID (for polling completion). */
    @Column(name = "textract_job_id", length = 200)
    private String textractJobId;

    @Column(name = "dispute_reason", length = 50)
    private String disputeReason;

    @Column(name = "dispute_description", columnDefinition = "TEXT")
    private String disputeDescription;

    @Column(name = "payment_due_date")
    private LocalDate paymentDueDate;

    @Column(name = "paid_at")
    private Instant paidAt;

    @Column(name = "auto_approved")
    @Builder.Default
    private boolean autoApproved = false;

    @Column(name = "approved_at")
    private Instant approvedAt;

    @Column(name = "approved_by", length = 100)
    private String approvedBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;

    @Version
    @Column(name = "version")
    private Long version;

    @OneToMany(mappedBy = "invoice", cascade = CascadeType.ALL, orphanRemoval = true,
               fetch = FetchType.LAZY)
    @Builder.Default
    private List<InvoiceLineItem> lineItems = new ArrayList<>();

    public boolean hasDiscrepancy(BigDecimal threshold) {
        if (invoicedAmount == null || expectedAmount == null) return false;
        var diff = invoicedAmount.subtract(expectedAmount).abs();
        return diff.compareTo(threshold) > 0;
    }

    public double discrepancyPercentage() {
        if (invoicedAmount == null || expectedAmount == null
                || expectedAmount.compareTo(BigDecimal.ZERO) == 0) return 0;
        return invoicedAmount.subtract(expectedAmount)
                .divide(expectedAmount, 4, java.math.RoundingMode.HALF_UP)
                .multiply(new BigDecimal("100"))
                .doubleValue();
    }
}
