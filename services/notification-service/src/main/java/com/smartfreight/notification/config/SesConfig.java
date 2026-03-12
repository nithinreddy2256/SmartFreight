package com.smartfreight.notification.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sesv2.SesV2Client;

import java.net.URI;

/**
 * Amazon SES v2 client configuration.
 *
 * <p>SES v2 is preferred over v1 for:
 * <ul>
 *   <li>Better deliverability features (Virtual Deliverability Manager)</li>
 *   <li>Topics-based subscription management</li>
 *   <li>Contact list management</li>
 *   <li>More detailed sending statistics</li>
 * </ul>
 *
 * <p>In local development with LocalStack, SES v2 is mocked and emails
 * are captured in LocalStack's email log (visible via LocalStack UI).
 * Actual emails are NOT sent in dev/test environments.
 */
@Configuration
public class SesConfig {

    @Value("${aws.region:us-east-1}")
    private String awsRegion;

    @Value("${aws.endpoint-url:#{null}}")
    private String endpointUrl;

    @Bean
    public SesV2Client sesV2Client() {
        var builder = SesV2Client.builder()
                .region(Region.of(awsRegion))
                .credentialsProvider(DefaultCredentialsProvider.create());
        if (endpointUrl != null) {
            builder.endpointOverride(URI.create(endpointUrl));
        }
        return builder.build();
    }
}
