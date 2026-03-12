package com.smartfreight.shipment.controller.dto;

import jakarta.validation.constraints.*;
import lombok.Data;

import java.math.BigDecimal;

/**
 * Request body for POST /api/shipments.
 * All @NotBlank fields are required. Others are optional.
 */
@Data
public class CreateShipmentRequest {

    @NotBlank(message = "Shipper ID is required")
    private String shipperId;

    @NotBlank(message = "Shipper name is required")
    @Size(max = 200)
    private String shipperName;

    @NotBlank(message = "Shipper email is required")
    @Email(message = "Shipper email must be a valid email address")
    private String shipperEmail;

    private String consigneeId;

    @Size(max = 200)
    private String consigneeName;

    @Email(message = "Consignee email must be a valid email address")
    private String consigneeEmail;

    // ─── Origin ────────────────────────────────────────────────────────────────
    private String originStreet;

    @NotBlank(message = "Origin city is required")
    @Size(max = 100)
    private String originCity;

    @NotBlank(message = "Origin state is required")
    @Size(max = 50)
    private String originState;

    @Size(max = 20)
    private String originZip;

    // ─── Destination ────────────────────────────────────────────────────────────
    private String destinationStreet;

    @NotBlank(message = "Destination city is required")
    @Size(max = 100)
    private String destinationCity;

    @NotBlank(message = "Destination state is required")
    @Size(max = 50)
    private String destinationState;

    @Size(max = 20)
    private String destinationZip;

    // ─── Freight Details ────────────────────────────────────────────────────────
    @Positive(message = "Weight must be greater than 0")
    private BigDecimal weightLbs;

    @PositiveOrZero(message = "Declared value must be 0 or greater")
    private BigDecimal declaredValue;

    @Size(max = 1000)
    private String specialInstructions;

    @Size(max = 20)
    private String glCode;
}
