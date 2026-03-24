package com.smartfreight.document.controller;

import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.document.controller.dto.RegisterDocumentRequest;
import com.smartfreight.document.domain.DocumentMetadata;
import com.smartfreight.document.repository.DocumentMetadataRepository;
import com.smartfreight.document.service.DocumentService;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/documents")
@RequiredArgsConstructor
public class DocumentController {

    private final DocumentService documentService;
    private final DocumentMetadataRepository metadataRepository;

    /** Step 1: Get a presigned PUT URL for direct browser-to-S3 upload. */
    @GetMapping("/presign-upload")
    public ApiResponse<DocumentService.PresignedUploadResult> presignUpload(
            @RequestParam String type,
            @RequestParam String shipmentId,
            @RequestParam(defaultValue = "pdf") String extension) {
        var result = documentService.generateUploadUrl(type, shipmentId, extension);
        return ApiResponse.ok(result, cid());
    }

    /** Step 2: Register document metadata after client finishes uploading to S3. */
    @PostMapping("/metadata")
    public ResponseEntity<ApiResponse<DocumentMetadata>> registerDocument(
            @Valid @RequestBody RegisterDocumentRequest req) {
        var metadata = new DocumentMetadata();
        metadata.setDocumentId(req.documentId());
        metadata.setShipmentId(req.shipmentId());
        metadata.setDocumentType(req.documentType());
        metadata.setS3Key(req.s3Key());
        metadata.setFileName(req.fileName());
        metadata.setContentType(req.contentType());
        metadata.setFileSizeBytes(req.fileSizeBytes());
        metadata.setUploadedBy(req.uploadedBy());
        metadata.setDescription(req.description());
        metadata.setStatus("UPLOADED");
        metadata.setUploadedAt(Instant.now());
        metadataRepository.save(metadata);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.ok(metadata, cid()));
    }

    /** Get a presigned GET URL for downloading a document. */
    @GetMapping("/{documentId}/download-url")
    public ApiResponse<String> downloadUrl(@PathVariable String documentId) {
        var metadata = metadataRepository.findById(documentId)
                .orElseThrow(() -> new NoSuchElementException("Document not found: " + documentId));
        var url = documentService.generateDownloadUrl(metadata.getS3Key());
        return ApiResponse.ok(url, cid());
    }

    /** Get document metadata by ID. */
    @GetMapping("/{documentId}")
    public ApiResponse<DocumentMetadata> getDocument(@PathVariable String documentId) {
        var metadata = metadataRepository.findById(documentId)
                .orElseThrow(() -> new NoSuchElementException("Document not found: " + documentId));
        return ApiResponse.ok(metadata, cid());
    }

    /** List all documents for a shipment. */
    @GetMapping("/shipment/{shipmentId}")
    public ApiResponse<List<DocumentMetadata>> listByShipment(@PathVariable String shipmentId) {
        return ApiResponse.ok(metadataRepository.findByShipmentId(shipmentId), cid());
    }

    private String cid() {
        return CorrelationIdFilter.getCurrentCorrelationId();
    }
}
