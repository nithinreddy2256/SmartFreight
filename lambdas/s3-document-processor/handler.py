"""
SmartFreight — S3 Document Processor Lambda
============================================
Triggered by S3 ObjectCreated events on the smartfreight-documents-{env} bucket.

S3 key format: {documentType}/{shipmentId}/{documentId}.{extension}
Example:       invoice/ship-abc-123/doc-xyz-456.pdf

Processing steps:
  1. Parse the S3 key to extract document type, shipment ID, document ID
  2. Upsert metadata into DynamoDB DocumentIndexTable
  3. Log result (errors are caught per-record so one failure doesn't block others)

Runtime: python3.12
Memory:  256 MB
Timeout: 30s
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

DOCUMENT_INDEX_TABLE = os.environ["DOCUMENT_INDEX_TABLE"]

CONTENT_TYPES = {
    "pdf":  "application/pdf",
    "jpg":  "image/jpeg",
    "jpeg": "image/jpeg",
    "png":  "image/png",
    "tif":  "image/tiff",
    "tiff": "image/tiff",
}


# ─── Entry point ──────────────────────────────────────────────────────────────

def handler(event: dict, context) -> dict:
    table = dynamodb.Table(DOCUMENT_INDEX_TABLE)
    records = event.get("Records", [])
    processed = 0
    failed = 0

    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        size_bytes = record["s3"]["object"].get("size", 0)

        logger.info("Processing S3 event. bucket=%s key=%s", bucket, key)

        try:
            _process_record(table, bucket, key, size_bytes)
            processed += 1
        except Exception as exc:
            logger.exception("Failed to process record. key=%s error=%s", key, exc)
            failed += 1

    logger.info("Batch complete. processed=%d failed=%d", processed, failed)
    return {"processed": processed, "failed": failed}


# ─── Core logic ───────────────────────────────────────────────────────────────

def _process_record(table, bucket: str, key: str, size_bytes: int) -> None:
    parts = key.split("/")

    if len(parts) < 3:
        logger.warning("Unexpected S3 key format (expected type/shipmentId/docId.ext): %s", key)
        return

    document_type = parts[0].upper()   # e.g. INVOICE
    shipment_id   = parts[1]           # e.g. ship-abc-123
    file_part     = parts[2]           # e.g. doc-xyz-456.pdf

    if "." in file_part:
        document_id, extension = file_part.rsplit(".", 1)
    else:
        document_id, extension = file_part, ""

    content_type = CONTENT_TYPES.get(extension.lower(), "application/octet-stream")
    now = datetime.now(timezone.utc).isoformat()

    item = {
        "documentId":   document_id,
        "shipmentId":   shipment_id,
        "documentType": document_type,
        "s3Key":        key,
        "s3Bucket":     bucket,
        "fileName":     file_part,
        "contentType":  content_type,
        "fileSizeBytes": size_bytes,
        "status":       "INDEXED",
        "indexedAt":    now,
    }

    # Use update_item so existing metadata (e.g. uploadedBy, description) is preserved
    table.update_item(
        Key={"documentId": document_id},
        UpdateExpression=(
            "SET shipmentId = :sid, documentType = :dt, s3Key = :sk, "
            "s3Bucket = :sb, fileName = :fn, contentType = :ct, "
            "fileSizeBytes = :fs, #st = :status, indexedAt = :ia"
        ),
        ExpressionAttributeNames={"#st": "status"},
        ExpressionAttributeValues={
            ":sid":    shipment_id,
            ":dt":     document_type,
            ":sk":     key,
            ":sb":     bucket,
            ":fn":     file_part,
            ":ct":     content_type,
            ":fs":     size_bytes,
            ":status": "INDEXED",
            ":ia":     now,
        },
    )

    logger.info(
        "Indexed document. documentId=%s shipmentId=%s type=%s size=%d",
        document_id, shipment_id, document_type, size_bytes,
    )
