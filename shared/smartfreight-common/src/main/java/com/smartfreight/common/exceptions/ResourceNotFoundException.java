package com.smartfreight.common.exceptions;

/**
 * Thrown when a requested resource does not exist.
 * Maps to HTTP 404 Not Found.
 *
 * <p>Usage:
 * <pre>
 * throw new ResourceNotFoundException("SHIPMENT_NOT_FOUND",
 *     "Shipment not found: " + shipmentId);
 * </pre>
 */
public class ResourceNotFoundException extends SmartFreightException {

    public ResourceNotFoundException(String errorCode, String message) {
        super(errorCode, message);
    }

    /** Convenience constructor for the common pattern. */
    public static ResourceNotFoundException shipment(String shipmentId) {
        return new ResourceNotFoundException(
                "SHIPMENT_NOT_FOUND",
                "Shipment not found: " + shipmentId
        );
    }

    public static ResourceNotFoundException carrier(String carrierId) {
        return new ResourceNotFoundException(
                "CARRIER_NOT_FOUND",
                "Carrier not found: " + carrierId
        );
    }

    public static ResourceNotFoundException invoice(String invoiceId) {
        return new ResourceNotFoundException(
                "INVOICE_NOT_FOUND",
                "Invoice not found: " + invoiceId
        );
    }

    public static ResourceNotFoundException document(String documentId) {
        return new ResourceNotFoundException(
                "DOCUMENT_NOT_FOUND",
                "Document not found: " + documentId
        );
    }
}
