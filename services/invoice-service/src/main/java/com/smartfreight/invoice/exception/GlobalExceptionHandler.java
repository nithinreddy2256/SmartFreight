package com.smartfreight.invoice.exception;

import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.common.dto.ErrorResponse;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.NoSuchElementException;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(NoSuchElementException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiResponse<Void> handleNotFound(NoSuchElementException ex) {
        return ApiResponse.error(
                ErrorResponse.builder().code("NOT_FOUND").message(ex.getMessage()).build(),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ApiResponse<Void> handleConflict(IllegalArgumentException ex) {
        return ApiResponse.error(
                ErrorResponse.builder().code("CONFLICT").message(ex.getMessage()).build(),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleValidation(MethodArgumentNotValidException ex) {
        String msg = ex.getBindingResult().getFieldErrors().stream()
                .map(fe -> fe.getField() + ": " + fe.getDefaultMessage())
                .findFirst().orElse("Validation failed");
        return ApiResponse.error(
                ErrorResponse.builder().code("VALIDATION_ERROR").message(msg).build(),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResponse<Void> handleGeneric(Exception ex) {
        log.error("Unhandled exception", ex);
        return ApiResponse.error(
                ErrorResponse.builder().code("INTERNAL_ERROR").message("An unexpected error occurred").build(),
                CorrelationIdFilter.getCurrentCorrelationId());
    }
}
