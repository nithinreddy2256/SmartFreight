package com.smartfreight.notification;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * SmartFreight Notification Service
 *
 * <p>Stateless, event-driven service that:
 * <ul>
 *   <li>Consumes all domain events from SQS notification-queue</li>
 *   <li>Renders branded HTML emails using Thymeleaf templates</li>
 *   <li>Sends emails via Amazon SES v2 API</li>
 *   <li>Tracks bounce/complaint rates via SES configuration set</li>
 * </ul>
 *
 * <p>No database — fully stateless. All required data is embedded in the events.
 * This is intentional: it means the service has no dependencies on other services
 * at runtime (no service-to-service calls needed to send a notification).
 */
@SpringBootApplication
public class NotificationServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(NotificationServiceApplication.class, args);
    }
}
