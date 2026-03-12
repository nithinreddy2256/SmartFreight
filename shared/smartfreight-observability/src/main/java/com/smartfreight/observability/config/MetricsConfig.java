package com.smartfreight.observability.config;

import io.micrometer.cloudwatch2.CloudWatchConfig;
import io.micrometer.cloudwatch2.CloudWatchMeterRegistry;
import io.micrometer.core.instrument.Clock;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tag;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.autoconfigure.metrics.MeterRegistryCustomizer;
import org.springframework.boot.autoconfigure.AutoConfiguration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import software.amazon.awssdk.services.cloudwatch.CloudWatchAsyncClient;

import java.time.Duration;
import java.util.List;

/**
 * Configures Micrometer metric publishing to Amazon CloudWatch.
 *
 * <p>CloudWatch metrics are only enabled when {@code management.cloudwatch.metrics.export.enabled=true}.
 * In local development this is false (metrics logged to console instead).
 * In dev/test/prod this is true (metrics published to CloudWatch every 60 seconds).
 *
 * <p>Each service publishes custom business metrics alongside the default JVM/HTTP metrics:
 * <ul>
 *   <li>shipment-service: shipment.created.count, shipment.processing.time, carrier.assignment.duration</li>
 *   <li>invoice-service: invoice.match.success.count, invoice.dispute.count, textract.latency</li>
 *   <li>notification-service: email.sent.count, email.failure.count</li>
 * </ul>
 *
 * <p>All metrics include these common tags: {@code service}, {@code environment}.
 * This enables CloudWatch filtering: "show me error rates for shipment-service in prod only."
 */
@AutoConfiguration
public class MetricsConfig {

    @Value("${spring.application.name:unknown}")
    private String serviceName;

    @Value("${spring.profiles.active:local}")
    private String environment;

    /**
     * Add service and environment tags to ALL metrics automatically.
     * This avoids having to specify tags on every metric definition.
     */
    @Bean
    public MeterRegistryCustomizer<MeterRegistry> commonTagsCustomizer() {
        return registry -> registry.config()
                .commonTags(List.of(
                        Tag.of("service", serviceName),
                        Tag.of("environment", environment)
                ));
    }

    /**
     * CloudWatch MeterRegistry — publishes metrics every 60 seconds.
     * Namespace in CloudWatch: SmartFreight/{environment}
     *
     * <p>Only instantiated when CloudWatch export is enabled.
     * Set {@code management.cloudwatch.metrics.export.enabled=true} in application-{env}.yml.
     */
    @Bean
    @ConditionalOnProperty(
            value = "management.cloudwatch.metrics.export.enabled",
            havingValue = "true")
    public CloudWatchMeterRegistry cloudWatchMeterRegistry(CloudWatchAsyncClient cloudWatchClient) {
        CloudWatchConfig config = new CloudWatchConfig() {
            @Override
            public String get(String key) {
                return null; // use defaults
            }

            @Override
            public String namespace() {
                return "SmartFreight/" + environment;
            }

            @Override
            public Duration step() {
                return Duration.ofSeconds(60);
            }
        };

        return new CloudWatchMeterRegistry(config, Clock.SYSTEM, cloudWatchClient);
    }

    /** Async CloudWatch client for non-blocking metric publishing. */
    @Bean
    @ConditionalOnProperty(
            value = "management.cloudwatch.metrics.export.enabled",
            havingValue = "true")
    public CloudWatchAsyncClient cloudWatchAsyncClient() {
        return CloudWatchAsyncClient.create();
    }
}
