package com.smartfreight.shipment;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * SmartFreight Shipment Service
 *
 * <p>Manages the full shipment lifecycle:
 * <ul>
 *   <li>Shipment creation with validation</li>
 *   <li>Carrier assignment with rate lookup (calls carrier-service)</li>
 *   <li>Status transitions enforced by ShipmentStatusMachine</li>
 *   <li>Tracking event ingestion from carrier webhooks (via SNS → SQS)</li>
 *   <li>Proof-of-delivery confirmation and document linking</li>
 * </ul>
 *
 * <p>Infrastructure:
 * <ul>
 *   <li>Database: Aurora PostgreSQL (shipment-db)</li>
 *   <li>Messaging: SNS (shipment-events topic) + SQS (shipment-inbound-queue)</li>
 *   <li>Cache: DynamoDB (TrackingEventTable for time-series tracking data)</li>
 *   <li>Config: Secrets Manager (DB credentials, resolved at startup)</li>
 * </ul>
 *
 * <p>Health check: GET /actuator/health
 * API documentation: GET /swagger-ui.html
 */
@SpringBootApplication
@EnableAsync
public class ShipmentServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(ShipmentServiceApplication.class, args);
    }
}
