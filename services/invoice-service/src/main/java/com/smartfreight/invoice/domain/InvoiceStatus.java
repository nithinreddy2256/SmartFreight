package com.smartfreight.invoice.domain;

/**
 * Invoice processing lifecycle states.
 *
 * <pre>
 * RECEIVED → OCR_PENDING → OCR_COMPLETE → MATCHING → APPROVED
 *                                                  ↘ DISPUTED
 * APPROVED → PAID (terminal)
 * DISPUTED → APPROVED (after manual review) or REJECTED (terminal)
 * </pre>
 */
public enum InvoiceStatus {
    /** Invoice received, document saved to S3. */
    RECEIVED,
    /** Amazon Textract async job started. */
    OCR_PENDING,
    /** Textract completed, fields extracted. */
    OCR_COMPLETE,
    /** 3-way match in progress. */
    MATCHING,
    /** Match passed — approved for payment. */
    APPROVED,
    /** Match failed — requires human review. */
    DISPUTED,
    /** Payment processed. Terminal state. */
    PAID,
    /** Rejected after review. Terminal state. */
    REJECTED
}
