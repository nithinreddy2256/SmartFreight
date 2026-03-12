package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.math.BigDecimal;

/**
 * Published when a freight invoice fails 3-way match and is flagged for review.
 *
 * <p>Consumers:
 * <ul>
 *   <li>notification-service: sends "Invoice Disputed" alert to AP team and carrier relations</li>
 *   <li>analytics-service: updates dispute rate metrics by carrier</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("InvoiceDisputedEvent")
public class InvoiceDisputedEvent extends BaseEvent {

    private String invoiceId;
    private String invoiceNumber;
    private String carrierId;
    private String carrierName;
    private String shipmentId;
    private String shipmentReferenceNumber;

    /** Amount the carrier invoiced. */
    private BigDecimal invoicedAmount;

    /** Amount SmartFreight expected based on contracted rate × actual weight. */
    private BigDecimal expectedAmount;

    /** Difference (invoicedAmount - expectedAmount). Positive = overcharge. */
    private BigDecimal discrepancyAmount;

    /** Percentage difference for threshold-based routing. */
    private double discrepancyPercentage;

    /** Reason code: OVERCHARGE, UNDERCHARGE, MISSING_REFERENCE, DUPLICATE, RATE_MISMATCH. */
    private String disputeReason;

    /** Human-readable explanation for the AP team. */
    private String disputeDescription;

    private String apTeamEmail;
    private String carrierRelationsEmail;
}
