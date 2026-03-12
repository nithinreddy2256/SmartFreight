package com.smartfreight.carrier.domain;

import lombok.*;
import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.*;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;

/**
 * DynamoDB entity representing a carrier rate card for a specific lane.
 *
 * <p>Table: CarrierRateTable
 * <ul>
 *   <li>Partition key: {@code carrierId} (e.g., "fedex", "ups", "dhl")</li>
 *   <li>Sort key: {@code laneId} (e.g., "TX-CA-LTL" = Texas to California LTL freight)</li>
 * </ul>
 *
 * <p>Access patterns:
 * <ul>
 *   <li>Get all rates for carrier (PK only): carrier-service admin</li>
 *   <li>Get rate for specific lane (PK + SK): carrier assignment flow</li>
 *   <li>GSI: laneId-carrierId-index for "find best carrier for this lane"</li>
 * </ul>
 */
@DynamoDbBean
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CarrierRate {

    /** Carrier identifier (partition key). */
    private String carrierId;

    /** Lane identifier: {originState}-{destState}-{shipmentType} (sort key). */
    private String laneId;

    /** Human-readable carrier name. */
    private String carrierName;

    /** Origin state abbreviation. */
    private String originState;

    /** Destination state abbreviation. */
    private String destinationState;

    /** Freight mode: LTL (less-than-truckload), FTL (full truckload), PARCEL. */
    private String shipmentType;

    /** Base rate per hundredweight (CWT) in USD. */
    private BigDecimal ratePerCwt;

    /** Fuel surcharge percentage (changes weekly). */
    private BigDecimal fuelSurchargePercent;

    /** Minimum charge regardless of weight. */
    private BigDecimal minimumCharge;

    /** Standard transit days for this lane. */
    private int transitDays;

    /** Date from which this rate is effective. */
    private LocalDate effectiveDate;

    /** Date on which this rate expires (null = no expiry). */
    private LocalDate expirationDate;

    /** Whether the carrier is currently accepting bookings on this lane. */
    private boolean active;

    /** Timestamp of last refresh from carrier API. */
    private Instant lastRefreshedAt;

    @DynamoDbPartitionKey
    public String getCarrierId() { return carrierId; }

    @DynamoDbSortKey
    public String getLaneId() { return laneId; }

    /**
     * Calculates the total rate for a given weight in pounds.
     * Formula: max(minimumCharge, (weight/100) * ratePerCwt * (1 + fuelSurchargePercent))
     */
    public BigDecimal calculateRate(BigDecimal weightLbs) {
        if (weightLbs == null || ratePerCwt == null) {
            return minimumCharge != null ? minimumCharge : BigDecimal.ZERO;
        }
        var cwt = weightLbs.divide(new BigDecimal("100"), 4, java.math.RoundingMode.HALF_UP);
        var baseCharge = cwt.multiply(ratePerCwt);
        var fuelMultiplier = BigDecimal.ONE.add(
                fuelSurchargePercent != null
                        ? fuelSurchargePercent.divide(new BigDecimal("100"), 4, java.math.RoundingMode.HALF_UP)
                        : BigDecimal.ZERO);
        var totalCharge = baseCharge.multiply(fuelMultiplier);
        return minimumCharge != null && totalCharge.compareTo(minimumCharge) < 0
                ? minimumCharge : totalCharge.setScale(2, java.math.RoundingMode.HALF_UP);
    }
}
