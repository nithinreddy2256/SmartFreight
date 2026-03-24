"""
SmartFreight — Carrier Webhook Handler Lambda
=============================================
Triggered by API Gateway HTTP API: POST /webhooks/carrier/{carrierId}

Processing steps:
  1. Validate HMAC-SHA256 signature from X-Hub-Signature-256 header
  2. Parse carrier-specific event payload
  3. Normalize to SmartFreight internal tracking event format
  4. Publish to SNS shipment-events topic with eventType=TrackingEventReceivedEvent

No framework — plain boto3 for fast cold starts.
Runtime: python3.12
Memory:  512 MB
Timeout: 30s
"""

import hashlib
import hmac
import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialized once at module load — reused across warm invocations
sns_client = boto3.client("sns")

SHIPMENT_EVENTS_TOPIC_ARN = os.environ["SHIPMENT_EVENTS_TOPIC_ARN"]


# ─── Entry point ──────────────────────────────────────────────────────────────

def handler(event: dict, context) -> dict:
    correlation_id = str(uuid.uuid4())
    logger.info(
        "Processing carrier webhook",
        extra={"requestId": context.aws_request_id, "correlationId": correlation_id},
    )

    try:
        carrier_id = _extract_carrier_id(event)
        body_raw = event.get("body") or ""

        if not body_raw.strip():
            return _response(400, {"error": "Empty request body"})

        # 1. Validate HMAC signature
        if not _validate_signature(event, carrier_id, body_raw):
            logger.warning("Invalid webhook signature. carrierId=%s", carrier_id)
            return _response(401, {"error": "Invalid signature"})

        # 2. Parse payload
        try:
            payload = json.loads(body_raw)
        except json.JSONDecodeError as exc:
            logger.error("Failed to parse JSON body: %s", exc)
            return _response(400, {"error": "Invalid JSON body"})

        # 3. Normalize to internal tracking event
        tracking_event = _normalize_carrier_event(carrier_id, payload, correlation_id)

        # 4. Publish to SNS
        _publish_to_sns(tracking_event, correlation_id)

        logger.info(
            "Webhook processed successfully. carrierId=%s shipmentId=%s status=%s",
            carrier_id,
            tracking_event.get("shipmentId"),
            tracking_event.get("carrierStatus"),
        )
        return _response(200, {"message": "OK", "correlationId": correlation_id})

    except Exception as exc:
        logger.exception("Failed to process webhook: %s", exc)
        return _response(500, {"error": "Internal server error"})


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _extract_carrier_id(event: dict) -> str:
    path_params = event.get("pathParameters") or {}
    return path_params.get("carrierId", "unknown")


def _validate_signature(event: dict, carrier_id: str, body_raw: str) -> bool:
    """Validate HMAC-SHA256 signature provided by the carrier."""
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    signature = headers.get("x-hub-signature-256")

    if not signature:
        logger.warning("No signature header present. carrierId=%s — permitting (dev mode)", carrier_id)
        return True  # In production: return False

    secret_env = f"WEBHOOK_SECRET_{carrier_id.upper()}"
    secret = os.environ.get(secret_env)
    if not secret:
        logger.warning("No webhook secret configured for carrierId=%s — skipping validation", carrier_id)
        return True

    expected = "sha256=" + hmac.new(
        secret.encode("utf-8"),
        body_raw.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


def _normalize_carrier_event(carrier_id: str, payload: dict, correlation_id: str) -> dict:
    """Normalize carrier-specific payload to SmartFreight internal format."""
    now = datetime.now(timezone.utc).isoformat()

    carrier = carrier_id.lower()

    if carrier == "fedex":
        tracking_info = payload.get("TrackingInfo", {})
        latest = tracking_info.get("latestStatus", {})
        scan_loc = latest.get("scanLocation", {})
        return {
            "shipmentId": tracking_info.get("customerTrackingId", ""),
            "carrierTrackingNumber": tracking_info.get("trackingNumber", ""),
            "carrierStatus": latest.get("statusCode", ""),
            "statusDescription": latest.get("description", ""),
            "location": f"{scan_loc.get('city', '')}, {scan_loc.get('stateOrProvinceCode', '')}",
            "carrierId": carrier_id,
            "correlationId": correlation_id,
            "timestamp": now,
        }

    elif carrier == "ups":
        shipment = payload.get("shipment", {})
        package = shipment.get("package", {})
        activities = package.get("activity", [{}])
        latest_activity = activities[0] if activities else {}
        status = latest_activity.get("status", {})
        address = latest_activity.get("location", {}).get("address", {})
        return {
            "shipmentId": shipment.get("referenceNumber", ""),
            "carrierTrackingNumber": package.get("trackingNumber", ""),
            "carrierStatus": status.get("type", ""),
            "statusDescription": latest_activity.get("description", ""),
            "location": f"{address.get('city', '')}, {address.get('stateProvince', '')}",
            "carrierId": carrier_id,
            "correlationId": correlation_id,
            "timestamp": now,
        }

    elif carrier == "dhl":
        shipment_tracking = payload.get("shipmentTrackingNumber", "")
        events = payload.get("events", [{}])
        latest_event = events[0] if events else {}
        location = latest_event.get("location", {}).get("address", {})
        return {
            "shipmentId": payload.get("customerReference", shipment_tracking),
            "carrierTrackingNumber": shipment_tracking,
            "carrierStatus": latest_event.get("status", ""),
            "statusDescription": latest_event.get("description", ""),
            "location": f"{location.get('addressLocality', '')}, {location.get('countryCode', '')}",
            "carrierId": carrier_id,
            "correlationId": correlation_id,
            "timestamp": now,
        }

    else:
        # Generic format — expect SmartFreight internal format
        return {
            "shipmentId": payload.get("shipmentId", ""),
            "carrierTrackingNumber": payload.get("trackingNumber", ""),
            "carrierStatus": payload.get("status", ""),
            "statusDescription": payload.get("description", ""),
            "location": payload.get("location", ""),
            "carrierId": carrier_id,
            "correlationId": correlation_id,
            "timestamp": now,
        }


def _publish_to_sns(tracking_event: dict, correlation_id: str) -> None:
    sns_client.publish(
        TopicArn=SHIPMENT_EVENTS_TOPIC_ARN,
        Message=json.dumps(tracking_event),
        MessageAttributes={
            "eventType": {
                "DataType": "String",
                "StringValue": "TrackingEventReceivedEvent",
            },
            "correlationId": {
                "DataType": "String",
                "StringValue": correlation_id,
            },
            "carrierId": {
                "DataType": "String",
                "StringValue": tracking_event.get("carrierId", "unknown"),
            },
        },
    )


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
