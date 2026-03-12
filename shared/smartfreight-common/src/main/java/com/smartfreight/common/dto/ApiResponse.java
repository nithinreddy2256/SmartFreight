package com.smartfreight.common.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;
import lombok.Getter;

import java.time.Instant;

/**
 * Standard API response envelope used by all SmartFreight REST endpoints.
 *
 * <p>All successful responses are wrapped in this object:
 * <pre>
 * {
 *   "success": true,
 *   "data": { ... },
 *   "correlationId": "abc-123",
 *   "timestamp": "2024-03-10T14:32:00Z"
 * }
 * </pre>
 *
 * <p>Error responses use {@code success: false} with a populated {@code error} field
 * and {@code null} data. See {@link ErrorResponse} for the error structure.
 *
 * @param <T> type of the response body
 */
@Getter
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {

    private final boolean success;
    private final T data;
    private final ErrorResponse error;
    private final String correlationId;
    private final Instant timestamp;

    /** Factory: wrap a successful result. */
    public static <T> ApiResponse<T> ok(T data, String correlationId) {
        return ApiResponse.<T>builder()
                .success(true)
                .data(data)
                .correlationId(correlationId)
                .timestamp(Instant.now())
                .build();
    }

    /** Factory: wrap an error result. */
    public static <T> ApiResponse<T> error(ErrorResponse error, String correlationId) {
        return ApiResponse.<T>builder()
                .success(false)
                .error(error)
                .correlationId(correlationId)
                .timestamp(Instant.now())
                .build();
    }
}
