package com.smartfreight.shipment.controller.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.Data;

/**
 * Request body for PUT /api/shipments/{id}/status.
 */
@Data
public class UpdateStatusRequest {

    @NotBlank(message = "Status is required")
    @Pattern(regexp = "CARRIER_ASSIGNED|PICKED_UP|IN_TRANSIT|OUT_FOR_DELIVERY|DELIVERED|EXCEPTION|CANCELLED",
             message = "Invalid shipment status")
    private String status;

    /** Required when status = DELIVERED. Name of person who signed for the delivery. */
    private String recipientName;

    /** Required when status = DELIVERED. S3 key of uploaded proof of delivery document. */
    private String podDocumentKey;

    /** Carrier-reported reason for this status change. */
    private String statusReason;

    /** Location where this status change occurred. */
    private String location;
}
