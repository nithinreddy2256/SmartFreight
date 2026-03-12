package com.smartfreight.common.exceptions;

/**
 * Thrown when a business rule is violated (as opposed to an infrastructure error).
 * Maps to HTTP 422 Unprocessable Entity.
 *
 * <p>Examples:
 * <ul>
 *   <li>Attempting to cancel a DELIVERED shipment</li>
 *   <li>Assigning a carrier without available capacity for the lane</li>
 *   <li>Approving an invoice that has already been paid</li>
 * </ul>
 */
public class BusinessRuleViolationException extends SmartFreightException {

    public BusinessRuleViolationException(String errorCode, String message) {
        super(errorCode, message);
    }

    public static BusinessRuleViolationException invalidStatusTransition(
            String shipmentId, String fromStatus, String toStatus) {
        return new BusinessRuleViolationException(
                "INVALID_STATUS_TRANSITION",
                String.format("Cannot transition shipment %s from %s to %s",
                        shipmentId, fromStatus, toStatus)
        );
    }

    public static BusinessRuleViolationException carrierCapacityExceeded(
            String carrierId, String laneId) {
        return new BusinessRuleViolationException(
                "CARRIER_CAPACITY_EXCEEDED",
                String.format("Carrier %s has no available capacity for lane %s",
                        carrierId, laneId)
        );
    }

    public static BusinessRuleViolationException invoiceAlreadyProcessed(String invoiceId) {
        return new BusinessRuleViolationException(
                "INVOICE_ALREADY_PROCESSED",
                "Invoice has already been processed: " + invoiceId
        );
    }
}
