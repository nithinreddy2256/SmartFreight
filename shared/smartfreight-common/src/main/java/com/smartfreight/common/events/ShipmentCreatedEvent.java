package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.time.Instant;

/**
 * Published to SNS {@code shipment-events} topic when a new shipment is created.
 *
 * <p>Consumers:
 * <ul>
 *   <li>notification-service — sends "Shipment Created" confirmation email to shipper</li>
 *   <li>analytics-service — increments daily shipment creation counter</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("ShipmentCreatedEvent")
public class ShipmentCreatedEvent extends BaseEvent {

    /** SmartFreight internal shipment ID (UUID). */
    private String shipmentId;

    /** Human-readable reference number shown on shipping labels (e.g., SF-2024-001234). */
    private String referenceNumber;

    /** ID of the shipper (customer who created the shipment). */
    private String shipperId;

    /** Name of the shipper company for display in notifications. */
    private String shipperName;

    /** Email address of the shipper contact for notifications. */
    private String shipperEmail;

    /** ID of the consignee (recipient). */
    private String consigneeId;

    /** Name of the consignee for display in notifications. */
    private String consigneeName;

    /** Email address of the consignee for delivery notifications. */
    private String consigneeEmail;

    /** Origin city, state for display. */
    private String originCity;

    /** Destination city, state for display. */
    private String destinationCity;

    /** Assigned carrier ID (may be null if not yet assigned). */
    private String carrierId;

    /** Assigned carrier name for display. */
    private String carrierName;

    /** Estimated delivery date. */
    private Instant estimatedDelivery;

    /** Total weight in pounds. */
    private Double weightLbs;

    /** Total shipment value in USD (for insurance purposes). */
    private Double declaredValue;
}
