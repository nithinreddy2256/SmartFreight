package com.smartfreight.document.controller.dto;

import jakarta.validation.constraints.NotBlank;

public record RegisterDocumentRequest(
        @NotBlank String documentId,
        @NotBlank String shipmentId,
        @NotBlank String documentType,
        @NotBlank String s3Key,
        String fileName,
        String contentType,
        Long fileSizeBytes,
        String uploadedBy,
        String description
) {}
