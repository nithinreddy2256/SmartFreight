package com.smartfreight.document.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.util.UUID;

/**
 * Core document management service.
 *
 * <p>Upload flow:
 * <ol>
 *   <li>Client calls GET /api/documents/presign-upload?type=INVOICE&shipmentId=xxx</li>
 *   <li>Service generates a presigned PUT URL for S3 (15-minute expiry)</li>
 *   <li>Client uploads the file directly to S3 using the presigned URL</li>
 *   <li>Client calls POST /api/documents/metadata to register the document</li>
 *   <li>Service saves metadata to DynamoDB DocumentIndexTable</li>
 *   <li>S3 ObjectCreated event triggers Lambda s3-document-processor</li>
 * </ol>
 *
 * <p>Download flow:
 * <ol>
 *   <li>Client calls GET /api/documents/{id}/download-url</li>
 *   <li>Service generates a presigned GET URL for S3 (1-hour expiry)</li>
 *   <li>Client downloads directly from S3 using the presigned URL</li>
 * </ol>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class DocumentService {

    private final S3Presigner s3Presigner;
    private final S3Client s3Client;

    @Value("${aws.s3.documents-bucket-name}")
    private String documentsBucket;

    /** Upload URL expiry — 15 minutes (enough for large PDF uploads on slow connections). */
    private static final Duration UPLOAD_URL_EXPIRY = Duration.ofMinutes(15);

    /** Download URL expiry — 1 hour (for viewing in browser). */
    private static final Duration DOWNLOAD_URL_EXPIRY = Duration.ofHours(1);

    /**
     * Generates a presigned PUT URL for direct browser-to-S3 upload.
     *
     * @param documentType  type of document: INVOICE, BILL_OF_LADING, POD, RATE_CONFIRMATION
     * @param shipmentId    associated shipment ID (used in S3 key path)
     * @param fileExtension file extension: pdf, jpg, png
     * @return S3 key (for later reference) and presigned URL
     */
    public PresignedUploadResult generateUploadUrl(String documentType, String shipmentId,
                                                    String fileExtension) {
        var documentId = UUID.randomUUID().toString();
        var s3Key = buildS3Key(documentType, shipmentId, documentId, fileExtension);

        var putObjectRequest = PutObjectRequest.builder()
                .bucket(documentsBucket)
                .key(s3Key)
                .contentType(resolveContentType(fileExtension))
                .build();

        var presignRequest = PutObjectPresignRequest.builder()
                .signatureDuration(UPLOAD_URL_EXPIRY)
                .putObjectRequest(putObjectRequest)
                .build();

        var presignedRequest = s3Presigner.presignPutObject(presignRequest);

        log.info("Generated presigned upload URL. documentId={} type={} shipmentId={} key={}",
                documentId, documentType, shipmentId, s3Key);

        return new PresignedUploadResult(documentId, s3Key, presignedRequest.url().toString(),
                UPLOAD_URL_EXPIRY.toMinutes());
    }

    /**
     * Generates a presigned GET URL for direct browser download from S3.
     *
     * @param s3Key S3 object key of the document
     * @return presigned download URL
     */
    public String generateDownloadUrl(String s3Key) {
        var getObjectRequest = GetObjectRequest.builder()
                .bucket(documentsBucket)
                .key(s3Key)
                .build();

        var presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(DOWNLOAD_URL_EXPIRY)
                .getObjectRequest(getObjectRequest)
                .build();

        var presignedRequest = s3Presigner.presignGetObject(presignRequest);
        return presignedRequest.url().toString();
    }

    private String buildS3Key(String documentType, String shipmentId,
                               String documentId, String extension) {
        // Key structure: {documentType}/{shipmentId}/{documentId}.{extension}
        // Example: INVOICE/ship-abc-123/doc-xyz-456.pdf
        return documentType.toLowerCase() + "/" + shipmentId + "/" + documentId + "." + extension;
    }

    private String resolveContentType(String extension) {
        return switch (extension.toLowerCase()) {
            case "pdf" -> "application/pdf";
            case "jpg", "jpeg" -> "image/jpeg";
            case "png" -> "image/png";
            default -> "application/octet-stream";
        };
    }

    public record PresignedUploadResult(
            String documentId,
            String s3Key,
            String uploadUrl,
            long expiresInMinutes
    ) {}
}
