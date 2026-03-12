package com.smartfreight.document;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * SmartFreight Document Service
 *
 * <p>Manages all document storage and retrieval:
 * <ul>
 *   <li>Generates presigned S3 upload URLs (15-minute expiry)</li>
 *   <li>Generates presigned S3 download URLs (1-hour expiry)</li>
 *   <li>Maintains DynamoDB DocumentIndexTable for fast metadata lookup</li>
 *   <li>Supports document types: BILL_OF_LADING, INVOICE, POD, RATE_CONFIRMATION</li>
 * </ul>
 *
 * <p>Design rationale for presigned URLs:
 * Browsers/clients upload directly to S3, bypassing this service.
 * This eliminates network bandwidth costs and latency for large files.
 * The service only handles metadata and URL generation.
 */
@SpringBootApplication
public class DocumentServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(DocumentServiceApplication.class, args);
    }
}
