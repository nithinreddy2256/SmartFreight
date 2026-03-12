package com.smartfreight.shipment.exception;

import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.common.dto.ErrorResponse;
import com.smartfreight.common.exceptions.BusinessRuleViolationException;
import com.smartfreight.common.exceptions.ExternalServiceException;
import com.smartfreight.common.exceptions.ResourceNotFoundException;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

/**
 * Global exception handler for all REST endpoints.
 *
 * <p>Converts exceptions to consistent {@link ApiResponse} error responses:
 * <ul>
 *   <li>ResourceNotFoundException → 404</li>
 *   <li>BusinessRuleViolationException → 422</li>
 *   <li>MethodArgumentNotValidException → 400</li>
 *   <li>ExternalServiceException → 502</li>
 *   <li>All others → 500</li>
 * </ul>
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ApiResponse<Void>> handleResourceNotFound(ResourceNotFoundException ex) {
        log.warn("Resource not found: {} - {}", ex.getErrorCode(), ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error(
                        ErrorResponse.builder()
                                .code(ex.getErrorCode())
                                .message(ex.getMessage())
                                .build(),
                        CorrelationIdFilter.getCurrentCorrelationId()));
    }

    @ExceptionHandler(BusinessRuleViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusinessRuleViolation(
            BusinessRuleViolationException ex) {
        log.warn("Business rule violation: {} - {}", ex.getErrorCode(), ex.getMessage());
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body(ApiResponse.error(
                        ErrorResponse.builder()
                                .code(ex.getErrorCode())
                                .message(ex.getMessage())
                                .build(),
                        CorrelationIdFilter.getCurrentCorrelationId()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidationErrors(
            MethodArgumentNotValidException ex) {
        var fieldErrors = ex.getBindingResult().getFieldErrors().stream()
                .collect(Collectors.toMap(
                        FieldError::getField,
                        fe -> fe.getDefaultMessage() != null ? fe.getDefaultMessage() : "Invalid value",
                        (existing, replacement) -> existing));

        log.warn("Validation failed: {}", fieldErrors);
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.error(
                        ErrorResponse.builder()
                                .code("VALIDATION_ERROR")
                                .message("Request validation failed")
                                .fieldErrors(fieldErrors)
                                .build(),
                        CorrelationIdFilter.getCurrentCorrelationId()));
    }

    @ExceptionHandler(ExternalServiceException.class)
    public ResponseEntity<ApiResponse<Void>> handleExternalServiceError(
            ExternalServiceException ex) {
        log.error("External service error: service={} message={}", ex.getServiceName(),
                ex.getMessage(), ex);
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(ApiResponse.error(
                        ErrorResponse.builder()
                                .code(ex.getErrorCode())
                                .message("External service temporarily unavailable: " + ex.getServiceName())
                                .build(),
                        CorrelationIdFilter.getCurrentCorrelationId()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleGenericError(Exception ex) {
        log.error("Unexpected error", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error(
                        ErrorResponse.builder()
                                .code("INTERNAL_ERROR")
                                .message("An unexpected error occurred")
                                .build(),
                        CorrelationIdFilter.getCurrentCorrelationId()));
    }
}
