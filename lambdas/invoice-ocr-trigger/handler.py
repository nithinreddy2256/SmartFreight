"""
SmartFreight — Invoice OCR Trigger Lambda
==========================================
Triggered by S3 ObjectCreated events on invoice documents
(key prefix: invoice/).

Flow:
  1. Confirm the uploaded file is an invoice document (key starts with "invoice/")
  2. Start Amazon Textract async ExpenseAnalysis job
  3. Send a message to invoice-processing-queue with the Textract job ID
     so invoice-service can poll for completion and parse the result

Runtime: python3.12
Memory:  256 MB
Timeout: 60s
"""

import json
import logging
import os
import re
import urllib.parse
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client("textract")
sqs      = boto3.client("sqs")

INVOICE_QUEUE_URL           = os.environ["INVOICE_PROCESSING_QUEUE_URL"]
TEXTRACT_COMPLETION_TOPIC   = os.environ.get("TEXTRACT_COMPLETION_TOPIC_ARN", "")
TEXTRACT_ROLE_ARN           = os.environ.get("TEXTRACT_ROLE_ARN", "")

SUPPORTED_EXTENSIONS = re.compile(r"\.(pdf|jpg|jpeg|png|tiff?)$", re.IGNORECASE)


# ─── Entry point ──────────────────────────────────────────────────────────────

def handler(event: dict, context) -> dict:
    records = event.get("Records", [])
    started = 0
    skipped = 0
    failed  = 0

    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        key    = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        logger.info("S3 event received. bucket=%s key=%s", bucket, key)

        # Only process invoice documents
        if not key.lower().startswith("invoice/"):
            logger.info("Skipping non-invoice document. key=%s", key)
            skipped += 1
            continue

        if not SUPPORTED_EXTENSIONS.search(key):
            logger.info("Skipping unsupported file type. key=%s", key)
            skipped += 1
            continue

        try:
            job_id = _start_textract_job(bucket, key)
            logger.info("Textract job started. jobId=%s key=%s", job_id, key)

            _notify_invoice_service(job_id, key, bucket)
            started += 1

        except Exception as exc:
            logger.exception("Failed to start OCR. key=%s error=%s", key, exc)
            failed += 1

    logger.info("Batch complete. started=%d skipped=%d failed=%d", started, skipped, failed)
    return {"started": started, "skipped": skipped, "failed": failed}


# ─── Textract ─────────────────────────────────────────────────────────────────

def _start_textract_job(bucket: str, key: str) -> str:
    """Start Textract async ExpenseAnalysis; returns job ID."""
    request = {
        "Document": {
            "S3Object": {"Bucket": bucket, "Name": key}
        }
    }

    # Wire SNS completion notification if configured
    if TEXTRACT_COMPLETION_TOPIC and TEXTRACT_ROLE_ARN:
        request["NotificationChannel"] = {
            "SNSTopicArn": TEXTRACT_COMPLETION_TOPIC,
            "RoleArn":     TEXTRACT_ROLE_ARN,
        }

    response = textract.start_expense_analysis(**request)
    return response["JobId"]


# ─── SQS notification ─────────────────────────────────────────────────────────

def _notify_invoice_service(job_id: str, s3_key: str, bucket: str) -> None:
    """
    Send a message to the invoice-processing-queue so invoice-service
    can associate the Textract job with the correct invoice record.

    Key format: invoice/{shipmentId}/{documentId}.{ext}
    """
    parts = s3_key.split("/")
    shipment_id = parts[1] if len(parts) >= 2 else "unknown"
    file_part   = parts[2] if len(parts) >= 3 else s3_key
    document_id = file_part.rsplit(".", 1)[0] if "." in file_part else file_part

    message = {
        "eventType":     "OcrJobStartedEvent",
        "textractJobId": job_id,
        "documentId":    document_id,
        "shipmentId":    shipment_id,
        "s3Key":         s3_key,
        "s3Bucket":      bucket,
        "startedAt":     datetime.now(timezone.utc).isoformat(),
    }

    sqs.send_message(
        QueueUrl=INVOICE_QUEUE_URL,
        MessageBody=json.dumps(message),
        MessageAttributes={
            "eventType": {
                "DataType":    "String",
                "StringValue": "OcrJobStartedEvent",
            }
        },
    )

    logger.info(
        "Published OcrJobStartedEvent. jobId=%s documentId=%s shipmentId=%s",
        job_id, document_id, shipment_id,
    )
