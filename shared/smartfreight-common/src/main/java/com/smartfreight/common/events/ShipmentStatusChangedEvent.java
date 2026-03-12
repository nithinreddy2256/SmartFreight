package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

/**
 * Published when a shipment transitions between lifecycle states.
 *
 * <p>Valid transitions (enforced by ShipmentStatusMachine in shipment-service):
 * <pre>
 * CREATED → CARRIER_ASSIGNED → PICKED_UP → IN_TRANSIT → OUT_FOR_DELIVERY → DELIVERED
 *                                                       ↘ EXCEPTION ↗
 * Any state → CANCELLED (manual cancellation only)
 * </pre>
 *
 * <p>Consumers filter by {@code newStatus} to react to specific transitions:
 * <ul>
 *   <li>notification-service: IN_TRANSIT → "Shipment is on the way" email</li>
 *   <li>notification-service: OUT_FOR_DELIVERY → "Out for delivery today" email</li>
 *   <li>analytics-service: all transitions → status histogram metrics</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("ShipmentStatusChangedEvent")
public class ShipmentStatusChangedEvent extends BaseEvent {

    private String shipmentId;
    private String referenceNumber;
    private String oldStatus;
    private String newStatus;

    /** Carrier-reported reason for status change (e.g., "Package scanned at facility"). */
    private String statusReason;

    /** Location where the status change occurred (city, state or facility code). */
    private String location;

    /** Shipper email — passed through to avoid notification-service calling shipment-service. */
    private String shipperEmail;

    /** Consignee email for direct delivery notifications. */
    private String consigneeEmail;

    /** Human-readable shipment reference for email subject lines. */
    private String referenceDisplayName;
}
