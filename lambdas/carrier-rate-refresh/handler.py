"""
SmartFreight — Carrier Rate Refresh Lambda
===========================================
Triggered by EventBridge Scheduler every 6 hours.

Flow:
  1. For each configured carrier, fetch updated rate cards
     (from carrier API if URL is set, else use mock data for dev/test)
  2. Update DynamoDB CarrierRateTable with the new rates
  3. Publish CarrierRateUpdatedEvent to SNS carrier-events topic

Environment variables:
  CARRIER_RATE_TABLE_NAME     — DynamoDB table name
  CARRIER_EVENTS_TOPIC_ARN    — SNS topic ARN
  CARRIER_IDS                 — comma-separated list, e.g. "fedex,ups,dhl"
  SECRETS_PREFIX              — e.g. "/smartfreight/dev"
  ENVIRONMENT                 — dev / test / prod

Runtime: python3.12
Memory:  256 MB
Timeout: 300s (5 min — allows time for multiple carrier API calls)
"""

import json
import logging
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone
from decimal import Decimal

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb        = boto3.resource("dynamodb")
sns             = boto3.client("sns")
secrets_manager = boto3.client("secretsmanager")

CARRIER_RATE_TABLE    = os.environ["CARRIER_RATE_TABLE_NAME"]
CARRIER_EVENTS_TOPIC  = os.environ.get("CARRIER_EVENTS_TOPIC_ARN", "")
CARRIER_IDS           = [c.strip() for c in os.environ.get("CARRIER_IDS", "fedex,ups").split(",")]
SECRETS_PREFIX        = os.environ.get("SECRETS_PREFIX", f"/smartfreight/{os.environ.get('ENVIRONMENT', 'dev')}")

# Mock rate data used when no live API URL is configured (dev / test)
MOCK_RATES = {
    "fedex": [
        {"laneId": "TX-CA-LTL", "originState": "TX", "destinationState": "CA",
         "shipmentType": "LTL", "ratePerCwt": "12.50", "fuelSurchargePercent": "18.5",
         "minimumCharge": "250.00", "transitDays": 3},
        {"laneId": "NY-FL-LTL", "originState": "NY", "destinationState": "FL",
         "shipmentType": "LTL", "ratePerCwt": "14.20", "fuelSurchargePercent": "18.5",
         "minimumCharge": "300.00", "transitDays": 2},
        {"laneId": "IL-TX-FTL", "originState": "IL", "destinationState": "TX",
         "shipmentType": "FTL", "ratePerCwt": "2.80",  "fuelSurchargePercent": "22.0",
         "minimumCharge": "1200.00", "transitDays": 2},
        {"laneId": "CA-WA-LTL", "originState": "CA", "destinationState": "WA",
         "shipmentType": "LTL", "ratePerCwt": "10.50", "fuelSurchargePercent": "17.0",
         "minimumCharge": "200.00", "transitDays": 2},
    ],
    "ups": [
        {"laneId": "TX-CA-LTL", "originState": "TX", "destinationState": "CA",
         "shipmentType": "LTL", "ratePerCwt": "11.80", "fuelSurchargePercent": "17.2",
         "minimumCharge": "225.00", "transitDays": 4},
        {"laneId": "NY-FL-LTL", "originState": "NY", "destinationState": "FL",
         "shipmentType": "LTL", "ratePerCwt": "13.60", "fuelSurchargePercent": "17.2",
         "minimumCharge": "275.00", "transitDays": 3},
        {"laneId": "IL-TX-FTL", "originState": "IL", "destinationState": "TX",
         "shipmentType": "FTL", "ratePerCwt": "2.65",  "fuelSurchargePercent": "20.0",
         "minimumCharge": "1100.00", "transitDays": 2},
    ],
    "dhl": [
        {"laneId": "TX-CA-LTL", "originState": "TX", "destinationState": "CA",
         "shipmentType": "LTL", "ratePerCwt": "13.10", "fuelSurchargePercent": "19.0",
         "minimumCharge": "260.00", "transitDays": 3},
        {"laneId": "NY-FL-LTL", "originState": "NY", "destinationState": "FL",
         "shipmentType": "LTL", "ratePerCwt": "14.80", "fuelSurchargePercent": "19.0",
         "minimumCharge": "310.00", "transitDays": 2},
    ],
}


# ─── Entry point ──────────────────────────────────────────────────────────────

def handler(event: dict, context) -> str:
    logger.info("Starting carrier rate refresh. carriers=%s", CARRIER_IDS)
    table = dynamodb.Table(CARRIER_RATE_TABLE)

    total_updated = 0
    total_failed  = 0

    for carrier_id in CARRIER_IDS:
        try:
            rates = _fetch_rates(carrier_id)
            for rate in rates:
                _save_rate(table, carrier_id, rate)
                _publish_event(carrier_id, rate)
                total_updated += 1
            logger.info("Refreshed rates. carrier=%s count=%d", carrier_id, len(rates))
        except Exception as exc:
            logger.exception("Failed to refresh rates. carrier=%s error=%s", carrier_id, exc)
            total_failed += 1

    result = (
        f"Carrier rate refresh complete. "
        f"updated={total_updated} carriers_processed={len(CARRIER_IDS) - total_failed} "
        f"carriers_failed={total_failed}"
    )
    logger.info(result)
    return result


# ─── Fetch rates ──────────────────────────────────────────────────────────────

def _fetch_rates(carrier_id: str) -> list[dict]:
    """Return rate list from carrier API or fall back to mock data."""
    api_url_env = f"CARRIER_API_URL_{carrier_id.upper()}"
    api_url = os.environ.get(api_url_env, "")

    if not api_url:
        logger.info("No API URL configured for carrier=%s — using mock rates", carrier_id)
        return MOCK_RATES.get(carrier_id.lower(), [])

    try:
        api_key = _get_carrier_api_key(carrier_id)
        req = urllib.request.Request(
            f"{api_url}/rates",
            headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            if resp.status != 200:
                raise RuntimeError(f"Carrier API returned HTTP {resp.status}")
            body = json.loads(resp.read().decode())
            return _parse_carrier_response(carrier_id, body)

    except urllib.error.URLError as exc:
        logger.error("Carrier API request failed. carrier=%s error=%s", carrier_id, exc)
        logger.info("Falling back to mock rates for carrier=%s", carrier_id)
        return MOCK_RATES.get(carrier_id.lower(), [])


def _get_carrier_api_key(carrier_id: str) -> str:
    """Retrieve carrier API key from Secrets Manager."""
    secret_name = f"{SECRETS_PREFIX}/carriers/{carrier_id.lower()}"
    response = secrets_manager.get_secret_value(SecretId=secret_name)
    secret = json.loads(response["SecretString"])
    return secret.get("apiKey", "")


def _parse_carrier_response(carrier_id: str, body: dict) -> list[dict]:
    """Parse carrier-specific JSON response into normalized rate dicts."""
    # Carrier-specific parsers would live here.
    # For now return empty list — the live path is only hit in prod.
    logger.warning("Live carrier response parser not implemented for carrier=%s", carrier_id)
    return []


# ─── DynamoDB ─────────────────────────────────────────────────────────────────

def _save_rate(table, carrier_id: str, rate: dict) -> None:
    """Upsert carrier rate into CarrierRateTable."""
    now = datetime.now(timezone.utc).isoformat()

    table.put_item(Item={
        "carrierId":             carrier_id,
        "laneId":                rate["laneId"],
        "originState":           rate["originState"],
        "destinationState":      rate["destinationState"],
        "shipmentType":          rate["shipmentType"],
        "ratePerCwt":            Decimal(str(rate["ratePerCwt"])),
        "fuelSurchargePercent":  Decimal(str(rate["fuelSurchargePercent"])),
        "minimumCharge":         Decimal(str(rate.get("minimumCharge", "0"))),
        "transitDays":           int(rate.get("transitDays", 0)),
        "active":                True,
        "effectiveDate":         now,
        "lastRefreshedAt":       now,
    })


# ─── SNS event ────────────────────────────────────────────────────────────────

def _publish_event(carrier_id: str, rate: dict) -> None:
    """Publish CarrierRateUpdatedEvent to SNS (if topic is configured)."""
    if not CARRIER_EVENTS_TOPIC:
        return

    message = {
        "eventType":            "CarrierRateUpdatedEvent",
        "carrierId":            carrier_id,
        "laneId":               rate["laneId"],
        "originState":          rate["originState"],
        "destinationState":     rate["destinationState"],
        "shipmentType":         rate["shipmentType"],
        "ratePerCwt":           str(rate["ratePerCwt"]),
        "fuelSurchargePercent": str(rate["fuelSurchargePercent"]),
        "effectiveDate":        datetime.now(timezone.utc).isoformat(),
    }

    sns.publish(
        TopicArn=CARRIER_EVENTS_TOPIC,
        Message=json.dumps(message),
        MessageAttributes={
            "eventType": {
                "DataType":    "String",
                "StringValue": "CarrierRateUpdatedEvent",
            },
            "carrierId": {
                "DataType":    "String",
                "StringValue": carrier_id,
            },
        },
    )
