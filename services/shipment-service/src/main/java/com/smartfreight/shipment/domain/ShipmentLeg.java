package com.smartfreight.shipment.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;
import java.util.UUID;

/**
 * Represents one leg of a multi-carrier shipment route.
 *
 * <p>Example: New York → Chicago (Leg 1, FedEx) then Chicago → Los Angeles (Leg 2, UPS).
 * Single-leg shipments have exactly one ShipmentLeg.
 */
@Entity
@Table(name = "shipment_legs", indexes = {
        @Index(name = "idx_legs_shipment_id", columnList = "shipment_id"),
        @Index(name = "idx_legs_carrier_id", columnList = "carrier_id")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ShipmentLeg {

    @Id
    @Column(name = "id", updatable = false, nullable = false, length = 36)
    @Builder.Default
    private String id = UUID.randomUUID().toString();

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "shipment_id", nullable = false)
    private Shipment shipment;

    /** Order of this leg in the route (1-based). */
    @Column(name = "sequence", nullable = false)
    private int sequence;

    @Column(name = "carrier_id", nullable = false, length = 36)
    private String carrierId;

    @Column(name = "carrier_name", length = 200)
    private String carrierName;

    @Column(name = "origin_city", nullable = false, length = 100)
    private String originCity;

    @Column(name = "origin_state", nullable = false, length = 50)
    private String originState;

    @Column(name = "dest_city", nullable = false, length = 100)
    private String destinationCity;

    @Column(name = "dest_state", nullable = false, length = 50)
    private String destinationState;

    @Column(name = "estimated_departure")
    private Instant estimatedDeparture;

    @Column(name = "actual_departure")
    private Instant actualDeparture;

    @Column(name = "estimated_arrival")
    private Instant estimatedArrival;

    @Column(name = "actual_arrival")
    private Instant actualArrival;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 30)
    @Builder.Default
    private ShipmentStatus status = ShipmentStatus.CREATED;
}
