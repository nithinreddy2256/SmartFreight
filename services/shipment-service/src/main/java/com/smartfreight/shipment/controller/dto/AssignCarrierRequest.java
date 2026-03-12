package com.smartfreight.shipment.controller.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Data;

/** Request body for POST /api/shipments/{id}/assign-carrier. */
@Data
public class AssignCarrierRequest {

    @NotBlank(message = "Carrier ID is required")
    private String carrierId;

    @NotBlank(message = "Carrier name is required")
    private String carrierName;

    /** DynamoDB rate card ID from carrier-service rate lookup. */
    private String rateId;
}
