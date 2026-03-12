package com.smartfreight.observability.filter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.annotation.Order;
import org.springframework.lang.NonNull;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * Servlet filter that establishes a correlation ID for each incoming HTTP request.
 *
 * <p>The correlation ID is:
 * <ol>
 *   <li>Read from the {@code X-Correlation-ID} request header (if provided by upstream)</li>
 *   <li>Generated as a new UUID if not present</li>
 *   <li>Stored in the SLF4J MDC as {@code correlationId}</li>
 *   <li>Added to the HTTP response as {@code X-Correlation-ID}</li>
 * </ol>
 *
 * <p>The MDC value is automatically included in every log line via logback-spring.xml.
 * Services propagate the ID to downstream calls via the {@code X-Correlation-ID} header,
 * and to SNS/SQS messages via the {@code correlationId} message attribute.
 *
 * <p>This enables end-to-end tracing:
 * carrier webhook → Lambda → SNS → SQS → shipment-service → SES email
 * All log lines share the same correlationId for easy CloudWatch Logs Insights queries.
 */
@Component
@Order(1)
public class CorrelationIdFilter extends OncePerRequestFilter {

    public static final String CORRELATION_ID_HEADER = "X-Correlation-ID";
    public static final String CORRELATION_ID_MDC_KEY = "correlationId";

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        String correlationId = request.getHeader(CORRELATION_ID_HEADER);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }

        // Store in MDC — included in all log lines during this request
        MDC.put(CORRELATION_ID_MDC_KEY, correlationId);

        // Echo back in response so callers can correlate logs
        response.setHeader(CORRELATION_ID_HEADER, correlationId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            // Always clear MDC to prevent leakage to next request on the same thread
            MDC.remove(CORRELATION_ID_MDC_KEY);
        }
    }

    /**
     * Get the current correlation ID from MDC (for use in async/messaging contexts).
     * Returns "no-correlation-id" if not set.
     */
    public static String getCurrentCorrelationId() {
        String correlationId = MDC.get(CORRELATION_ID_MDC_KEY);
        return correlationId != null ? correlationId : "no-correlation-id";
    }
}
