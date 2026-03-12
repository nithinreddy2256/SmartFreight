package com.smartfreight.common.exceptions;

/**
 * Root exception for all SmartFreight application exceptions.
 *
 * <p>Exception hierarchy:
 * <pre>
 * SmartFreightException
 *   ├── ResourceNotFoundException      → HTTP 404
 *   ├── BusinessRuleViolationException → HTTP 422
 *   ├── ValidationException            → HTTP 400
 *   ├── ExternalServiceException       → HTTP 502
 *   └── InsufficientPermissionException → HTTP 403
 * </pre>
 */
public class SmartFreightException extends RuntimeException {

    private final String errorCode;

    public SmartFreightException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public SmartFreightException(String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.errorCode = errorCode;
    }

    public String getErrorCode() {
        return errorCode;
    }
}
