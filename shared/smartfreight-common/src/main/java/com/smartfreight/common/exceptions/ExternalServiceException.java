package com.smartfreight.common.exceptions;

/**
 * Thrown when a call to an external service (carrier API, Textract, etc.) fails.
 * Maps to HTTP 502 Bad Gateway.
 *
 * <p>These exceptions are candidates for Resilience4j retry/circuit-breaker.
 */
public class ExternalServiceException extends SmartFreightException {

    private final String serviceName;

    public ExternalServiceException(String serviceName, String message, Throwable cause) {
        super("EXTERNAL_SERVICE_ERROR", message, cause);
        this.serviceName = serviceName;
    }

    public ExternalServiceException(String serviceName, String message) {
        super("EXTERNAL_SERVICE_ERROR", message);
        this.serviceName = serviceName;
    }

    public String getServiceName() {
        return serviceName;
    }
}
