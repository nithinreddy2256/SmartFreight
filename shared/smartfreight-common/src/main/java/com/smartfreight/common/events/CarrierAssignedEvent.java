package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

/**
 * Published when a carrier is assigned to a shipment.
 *
 * <p>Consumers:
 * <ul>
 *   <li>notification-service: sends carrier assignment confirmation to shipper</li>
 *   <li>carrier-service: updates carrier active shipment count for capacity tracking</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("CarrierAssignedEvent")
public class CarrierAssignedEvent extends BaseEvent {

    private String shipmentId;
    private String referenceNumber;
    private String carrierId;
    private String carrierName;
    private String rateId;
}
