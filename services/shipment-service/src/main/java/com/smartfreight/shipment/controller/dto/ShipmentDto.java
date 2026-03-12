package com.smartfreight.shipment.controller.dto;

import com.smartfreight.shipment.domain.Shipment;
import com.smartfreight.shipment.domain.ShipmentStatus;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Read model / API response DTO for shipments.
 * Derived from the Shipment domain entity.
 */
@Getter
@Builder
public class ShipmentDto {

    private String id;
    private String referenceNumber;
    private String shipperId;
    private String shipperName;
    private String consigneeName;
    private String originCity;
    private String originState;
    private String destinationCity;
    private String destinationState;
    private String carrierId;
    private String carrierName;
    private String carrierTrackingNumber;
    private ShipmentStatus status;
    private BigDecimal weightLbs;
    private BigDecimal declaredValue;
    private Instant estimatedDelivery;
    private Instant actualDelivery;
    private String glCode;
    private Instant createdAt;
    private Instant updatedAt;

    public static ShipmentDto from(Shipment shipment) {
        return ShipmentDto.builder()
                .id(shipment.getId())
                .referenceNumber(shipment.getReferenceNumber())
                .shipperId(shipment.getShipperId())
                .shipperName(shipment.getShipperName())
                .consigneeName(shipment.getConsigneeName())
                .originCity(shipment.getOriginCity())
                .originState(shipment.getOriginState())
                .destinationCity(shipment.getDestinationCity())
                .destinationState(shipment.getDestinationState())
                .carrierId(shipment.getCarrierId())
                .carrierName(shipment.getCarrierName())
                .carrierTrackingNumber(shipment.getCarrierTrackingNumber())
                .status(shipment.getStatus())
                .weightLbs(shipment.getWeightLbs())
                .declaredValue(shipment.getDeclaredValue())
                .estimatedDelivery(shipment.getEstimatedDelivery())
                .actualDelivery(shipment.getActualDelivery())
                .glCode(shipment.getGlCode())
                .createdAt(shipment.getCreatedAt())
                .updatedAt(shipment.getUpdatedAt())
                .build();
    }
}
