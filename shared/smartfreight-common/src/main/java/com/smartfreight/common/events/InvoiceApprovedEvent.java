package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

/**
 * Published when a freight invoice passes 3-way match and is auto-approved for payment.
 *
 * <p>Consumers:
 * <ul>
 *   <li>notification-service: sends "Invoice Approved" email to AP team</li>
 *   <li>analytics-service: updates approved spend totals by carrier and GL code</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("InvoiceApprovedEvent")
public class InvoiceApprovedEvent extends BaseEvent {

    private String invoiceId;
    private String invoiceNumber;
    private String carrierId;
    private String carrierName;
    private String shipmentId;
    private String shipmentReferenceNumber;

    /** Final approved amount (may differ from invoiced amount after adjustments). */
    private BigDecimal approvedAmount;
    private String currency;
    private String glCode;

    /** Invoice date for accounting period assignment. */
    private LocalDate invoiceDate;

    /** Payment due date (invoice date + carrier payment terms). */
    private LocalDate paymentDueDate;

    /** Whether this was auto-approved (true) or manually reviewed (false). */
    private boolean autoApproved;

    /** Approval timestamp. */
    private Instant approvedAt;

    /** AP team email for notification. */
    private String apTeamEmail;
}
