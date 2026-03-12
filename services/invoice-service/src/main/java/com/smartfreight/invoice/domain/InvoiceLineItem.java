package com.smartfreight.invoice.domain;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.util.UUID;

/** Individual line item on a freight invoice (e.g., base freight, fuel surcharge, accessorial). */
@Entity
@Table(name = "invoice_line_items")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class InvoiceLineItem {

    @Id
    @Column(name = "id", updatable = false, nullable = false, length = 36)
    @Builder.Default
    private String id = UUID.randomUUID().toString();

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "invoice_id", nullable = false)
    private Invoice invoice;

    @Column(name = "description", nullable = false, length = 200)
    private String description;

    /** Type: BASE_FREIGHT, FUEL_SURCHARGE, ACCESSORIAL, RESIDENTIAL_DELIVERY, etc. */
    @Column(name = "charge_type", length = 50)
    private String chargeType;

    @Column(name = "quantity", precision = 10, scale = 4)
    private BigDecimal quantity;

    @Column(name = "unit_price", precision = 10, scale = 4)
    private BigDecimal unitPrice;

    @Column(name = "total_amount", precision = 12, scale = 2, nullable = false)
    private BigDecimal totalAmount;

    @Column(name = "gl_code", length = 20)
    private String glCode;
}
