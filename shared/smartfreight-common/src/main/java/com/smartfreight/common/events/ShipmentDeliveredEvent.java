package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.time.Instant;

/**
 * Published when final delivery is confirmed (proof of delivery received).
 *
 * <p>This is the most consequential shipment event — it triggers:
 * <ul>
 *   <li>notification-service: "Delivered" confirmation email to shipper + consignee</li>
 *   <li>invoice-service: marks shipment eligible for carrier invoice matching</li>
 *   <li>carrier-service: updates carrier on-time delivery statistics</li>
 *   <li>analytics-service: updates daily delivery metrics and lane performance</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("ShipmentDeliveredEvent")
public class ShipmentDeliveredEvent extends BaseEvent {

    private String shipmentId;
    private String referenceNumber;
    private String carrierId;
    private String carrierName;

    /** Actual delivery timestamp (from carrier tracking system). */
    private Instant deliveredAt;

    /** Whether delivery was on time relative to estimated delivery date. */
    private boolean onTime;

    /** Number of days early (positive) or late (negative). */
    private int daysVariance;

    /** S3 object key of the proof of delivery (POD) document, if uploaded. */
    private String podDocumentKey;

    /** Delivery location (may differ from consignee address for pickup points). */
    private String deliveryLocation;

    /** Name of person who signed for the delivery. */
    private String recipientName;

    /** Contact emails for notifications. */
    private String shipperEmail;
    private String consigneeEmail;

    /** Total shipment value in USD (for notification display). */
    private Double declaredValue;
}
