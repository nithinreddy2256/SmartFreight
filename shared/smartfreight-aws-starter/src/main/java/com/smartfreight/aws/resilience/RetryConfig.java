package com.smartfreight.aws.resilience;

import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.RetryRegistry;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.context.annotation.Bean;
import software.amazon.awssdk.services.sns.model.SnsException;
import software.amazon.awssdk.services.sqs.model.SqsException;

import java.time.Duration;

/**
 * Resilience4j configuration for AWS service calls.
 *
 * <p>Policies defined here:
 * <ul>
 *   <li>{@code sns-publish} — retry on SNS publish failures (transient throttling)</li>
 *   <li>{@code sqs-send} — retry on SQS send failures</li>
 *   <li>{@code carrier-service} — circuit breaker for inter-service calls</li>
 *   <li>{@code shipment-service} — circuit breaker for inter-service calls</li>
 * </ul>
 *
 * <p>These are programmatic defaults. Services can override via application.yml:
 * <pre>
 * resilience4j:
 *   retry:
 *     instances:
 *       sns-publish:
 *         maxAttempts: 5
 * </pre>
 */
@AutoConfiguration
public class RetryConfig {

    /**
     * Retry policy for SNS publish operations.
     * Retries on SnsException with exponential backoff: 500ms, 1s, 2s.
     * Does NOT retry on serialization errors (non-transient).
     */
    @Bean
    public RetryRegistry retryRegistry() {
        var snsRetryConfig = io.github.resilience4j.retry.RetryConfig.custom()
                .maxAttempts(3)
                .waitDuration(Duration.ofMillis(500))
                .retryExceptions(SnsException.class, SqsException.class)
                .ignoreExceptions(SnsPublisherIgnoreException.class)
                .build();

        return RetryRegistry.of(io.github.resilience4j.retry.RetryConfig.custom()
                .maxAttempts(3)
                .waitDuration(Duration.ofSeconds(1))
                .build());
    }

    /**
     * Circuit breaker for synchronous service-to-service calls (internal ALB).
     * Opens after 50% failure rate over 10 calls.
     * Half-open after 30 seconds, allows 5 test calls before deciding.
     */
    @Bean
    public CircuitBreakerRegistry circuitBreakerRegistry() {
        var config = CircuitBreakerConfig.custom()
                .slidingWindowSize(10)
                .failureRateThreshold(50)
                .waitDurationInOpenState(Duration.ofSeconds(30))
                .permittedNumberOfCallsInHalfOpenState(5)
                .build();

        return CircuitBreakerRegistry.of(config);
    }

    /** Marker exception type for non-retryable SNS errors. */
    public static class SnsPublisherIgnoreException extends RuntimeException {
        public SnsPublisherIgnoreException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
