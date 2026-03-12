package com.smartfreight.common.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;
import lombok.Getter;

import java.util.List;
import java.util.Map;

/**
 * Structured error response body.
 *
 * <p>Example (validation error):
 * <pre>
 * {
 *   "code": "VALIDATION_ERROR",
 *   "message": "Request validation failed",
 *   "fieldErrors": {
 *     "originCity": "must not be blank",
 *     "weightLbs": "must be greater than 0"
 *   }
 * }
 * </pre>
 *
 * <p>Example (business rule violation):
 * <pre>
 * {
 *   "code": "INVALID_STATUS_TRANSITION",
 *   "message": "Cannot transition shipment SF-001 from DELIVERED to IN_TRANSIT"
 * }
 * </pre>
 */
@Getter
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ErrorResponse {

    /** Machine-readable error code for programmatic handling. */
    private final String code;

    /** Human-readable message for logging and display. */
    private final String message;

    /**
     * Field-level validation errors. Key = field name, value = error message.
     * Present only for VALIDATION_ERROR code.
     */
    private final Map<String, String> fieldErrors;

    /**
     * Additional error context for debugging (stack trace summary, downstream error).
     * NOT included in production responses.
     */
    private final List<String> details;
}
