package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Published when carrier rate cards are refreshed from external carrier APIs.
 *
 * <p>Consumers:
 * <ul>
 *   <li>notification-service: sends "Rate Updated" alert to procurement team</li>
 *   <li>analytics-service: logs rate change history for trend analysis</li>
 * </ul>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("CarrierRateUpdatedEvent")
public class CarrierRateUpdatedEvent extends BaseEvent {

    private String carrierId;
    private String carrierName;
    private String laneId;
    private String originRegion;
    private String destinationRegion;

    private BigDecimal previousRate;
    private BigDecimal newRate;
    private String currency;

    /** Percentage change (positive = rate increase, negative = decrease). */
    private double changePercentage;

    /** Date from which the new rate is effective. */
    private LocalDate effectiveDate;

    private String procurementTeamEmail;
}
