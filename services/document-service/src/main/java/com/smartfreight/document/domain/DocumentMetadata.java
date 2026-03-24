package com.smartfreight.document.domain;

import software.amazon.awssdk.enhanced.dynamodb.mapper.annotations.*;

import java.time.Instant;

/**
 * DynamoDB item representing document metadata in DocumentIndexTable.
 *
 * <p>Primary key: documentId (HASH)
 * GSI: shipmentId-index (shipmentId HASH) — for listing all documents of a shipment
 */
@DynamoDbBean
public class DocumentMetadata {

    private String documentId;
    private String shipmentId;
    private String documentType;   // INVOICE, BILL_OF_LADING, POD, RATE_CONFIRMATION
    private String s3Key;
    private String fileName;
    private String contentType;
    private Long fileSizeBytes;
    private String uploadedBy;
    private String status;         // UPLOADED, PROCESSING, INDEXED, FAILED
    private Instant uploadedAt;
    private Instant indexedAt;
    private String description;

    @DynamoDbPartitionKey
    public String getDocumentId() { return documentId; }
    public void setDocumentId(String documentId) { this.documentId = documentId; }

    @DynamoDbSecondaryPartitionKey(indexNames = "shipmentId-index")
    public String getShipmentId() { return shipmentId; }
    public void setShipmentId(String shipmentId) { this.shipmentId = shipmentId; }

    public String getDocumentType() { return documentType; }
    public void setDocumentType(String documentType) { this.documentType = documentType; }

    public String getS3Key() { return s3Key; }
    public void setS3Key(String s3Key) { this.s3Key = s3Key; }

    public String getFileName() { return fileName; }
    public void setFileName(String fileName) { this.fileName = fileName; }

    public String getContentType() { return contentType; }
    public void setContentType(String contentType) { this.contentType = contentType; }

    public Long getFileSizeBytes() { return fileSizeBytes; }
    public void setFileSizeBytes(Long fileSizeBytes) { this.fileSizeBytes = fileSizeBytes; }

    public String getUploadedBy() { return uploadedBy; }
    public void setUploadedBy(String uploadedBy) { this.uploadedBy = uploadedBy; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public Instant getUploadedAt() { return uploadedAt; }
    public void setUploadedAt(Instant uploadedAt) { this.uploadedAt = uploadedAt; }

    public Instant getIndexedAt() { return indexedAt; }
    public void setIndexedAt(Instant indexedAt) { this.indexedAt = indexedAt; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
}
