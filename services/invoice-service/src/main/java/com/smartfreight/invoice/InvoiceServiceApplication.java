package com.smartfreight.invoice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * SmartFreight Invoice Service
 *
 * <p>Manages the full freight invoice lifecycle:
 * <ol>
 *   <li>Invoice intake via document upload (triggers OCR Lambda)</li>
 *   <li>Textract OCR result processing (extract invoice fields)</li>
 *   <li>3-way match: invoiced amount vs. contracted rate × actual weight</li>
 *   <li>GL coding assignment based on shipment data</li>
 *   <li>Auto-approval (matched) or dispute workflow (discrepancy)</li>
 *   <li>Payment authorization and remittance advice generation</li>
 * </ol>
 *
 * <p>Database: Aurora PostgreSQL (invoice-db)
 * Messaging: SNS (invoice-events) + SQS (invoice-processing-queue)
 */
@SpringBootApplication
@EnableAsync
public class InvoiceServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(InvoiceServiceApplication.class, args);
    }
}
