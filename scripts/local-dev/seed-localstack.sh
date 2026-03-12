#!/usr/bin/env bash
# =============================================================================
# SmartFreight — LocalStack Seed Script
# =============================================================================
# Creates all required AWS resources in LocalStack for local development.
# Run AFTER docker-compose up (or executed automatically by localstack-init container).
#
# Usage (manual):
#   export AWS_ACCESS_KEY_ID=test
#   export AWS_SECRET_ACCESS_KEY=test
#   export AWS_DEFAULT_REGION=us-east-1
#   export AWS_ENDPOINT_URL=http://localhost:4566
#   bash scripts/local-dev/seed-localstack.sh
# =============================================================================

set -euo pipefail

ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"  # LocalStack fake account ID
ENV="dev"

echo "============================================================"
echo "SmartFreight LocalStack Seed Script"
echo "Endpoint: $ENDPOINT | Region: $REGION | Env: $ENV"
echo "============================================================"

# ─── Helper functions ─────────────────────────────────────────────────────────
aws_local() {
  aws --endpoint-url="$ENDPOINT" --region="$REGION" "$@"
}

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# ─── S3 Buckets ───────────────────────────────────────────────────────────────
log "Creating S3 buckets..."

buckets=(
  "smartfreight-documents-${ENV}"
  "smartfreight-etl-raw-${ENV}"
  "smartfreight-etl-processed-${ENV}"
  "smartfreight-reports-${ENV}"
  "smartfreight-alb-logs-${ENV}"
  "smartfreight-terraform-state"
)

for bucket in "${buckets[@]}"; do
  aws_local s3api create-bucket --bucket "$bucket" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || true
  log "  ✓ Bucket: $bucket"
done

# Enable versioning on documents bucket (important for prod — practice here)
aws_local s3api put-bucket-versioning \
  --bucket "smartfreight-documents-${ENV}" \
  --versioning-configuration Status=Enabled

log "S3 buckets created ✓"

# ─── SNS Topics ───────────────────────────────────────────────────────────────
log "Creating SNS topics..."

# Create shipment-events topic
SHIPMENT_EVENTS_ARN=$(aws_local sns create-topic \
  --name "shipment-events-${ENV}" \
  --query 'TopicArn' --output text)
log "  ✓ shipment-events ARN: $SHIPMENT_EVENTS_ARN"

# Create invoice-events topic
INVOICE_EVENTS_ARN=$(aws_local sns create-topic \
  --name "invoice-events-${ENV}" \
  --query 'TopicArn' --output text)
log "  ✓ invoice-events ARN: $INVOICE_EVENTS_ARN"

# Create alert-topic
ALERT_TOPIC_ARN=$(aws_local sns create-topic \
  --name "smartfreight-alerts-${ENV}" \
  --query 'TopicArn' --output text)
log "  ✓ alert-topic ARN: $ALERT_TOPIC_ARN"

# Create carrier-events topic
CARRIER_EVENTS_ARN=$(aws_local sns create-topic \
  --name "carrier-events-${ENV}" \
  --query 'TopicArn' --output text)
log "  ✓ carrier-events ARN: $CARRIER_EVENTS_ARN"

log "SNS topics created ✓"

# ─── SQS Queues ───────────────────────────────────────────────────────────────
log "Creating SQS queues..."

# Function to create a queue with its Dead Letter Queue
create_queue_with_dlq() {
  local queue_name="$1"
  local max_receive_count="${2:-3}"

  # Create DLQ first
  local dlq_url
  dlq_url=$(aws_local sqs create-queue \
    --queue-name "${queue_name}-dlq" \
    --attributes '{"MessageRetentionPeriod":"1209600"}' \
    --query 'QueueUrl' --output text)

  local dlq_arn
  dlq_arn=$(aws_local sqs get-queue-attributes \
    --queue-url "$dlq_url" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' --output text)

  # Create main queue with redrive policy pointing to DLQ
  local redrive_policy
  redrive_policy=$(printf '{"deadLetterTargetArn":"%s","maxReceiveCount":%d}' "$dlq_arn" "$max_receive_count")

  local queue_url
  queue_url=$(aws_local sqs create-queue \
    --queue-name "$queue_name" \
    --attributes "{
      \"VisibilityTimeout\": \"30\",
      \"MessageRetentionPeriod\": \"345600\",
      \"RedrivePolicy\": $(echo "$redrive_policy" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    }" \
    --query 'QueueUrl' --output text)

  echo "$queue_url"
  log "  ✓ Queue: $queue_name (DLQ: ${queue_name}-dlq)"
}

# Create all application queues
NOTIFICATION_QUEUE_URL=$(create_queue_with_dlq "notification-queue-${ENV}")
INVOICE_PROCESSING_QUEUE_URL=$(create_queue_with_dlq "invoice-processing-queue-${ENV}")
ANALYTICS_QUEUE_URL=$(create_queue_with_dlq "analytics-queue-${ENV}")
SHIPMENT_INBOUND_QUEUE_URL=$(create_queue_with_dlq "shipment-inbound-queue-${ENV}")
CARRIER_INBOUND_QUEUE_URL=$(create_queue_with_dlq "carrier-inbound-queue-${ENV}")

log "SQS queues created ✓"

# ─── SNS → SQS Subscriptions (Fan-out Pattern) ────────────────────────────────
log "Creating SNS → SQS subscriptions..."

# Helper to get queue ARN
get_queue_arn() {
  aws_local sqs get-queue-attributes \
    --queue-url "$1" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' --output text
}

NOTIFICATION_QUEUE_ARN=$(get_queue_arn "$NOTIFICATION_QUEUE_URL")
INVOICE_PROCESSING_QUEUE_ARN=$(get_queue_arn "$INVOICE_PROCESSING_QUEUE_URL")
ANALYTICS_QUEUE_ARN=$(get_queue_arn "$ANALYTICS_QUEUE_URL")
SHIPMENT_INBOUND_QUEUE_ARN=$(get_queue_arn "$SHIPMENT_INBOUND_QUEUE_URL")

# Subscribe notification-queue to shipment-events
aws_local sns subscribe \
  --topic-arn "$SHIPMENT_EVENTS_ARN" \
  --protocol sqs \
  --notification-endpoint "$NOTIFICATION_QUEUE_ARN" \
  --query 'SubscriptionArn' --output text > /dev/null
log "  ✓ shipment-events → notification-queue"

# Subscribe analytics-queue to shipment-events
aws_local sns subscribe \
  --topic-arn "$SHIPMENT_EVENTS_ARN" \
  --protocol sqs \
  --notification-endpoint "$ANALYTICS_QUEUE_ARN" \
  --query 'SubscriptionArn' --output text > /dev/null
log "  ✓ shipment-events → analytics-queue"

# Subscribe shipment-inbound-queue to shipment-events (for tracking events from Lambda)
aws_local sns subscribe \
  --topic-arn "$SHIPMENT_EVENTS_ARN" \
  --protocol sqs \
  --notification-endpoint "$SHIPMENT_INBOUND_QUEUE_ARN" \
  --attributes '{"FilterPolicy":"{\"eventType\":[\"TrackingEventReceivedEvent\"]}"}' \
  --query 'SubscriptionArn' --output text > /dev/null
log "  ✓ shipment-events → shipment-inbound-queue (filtered: TrackingEventReceivedEvent)"

# Subscribe notification-queue to invoice-events
aws_local sns subscribe \
  --topic-arn "$INVOICE_EVENTS_ARN" \
  --protocol sqs \
  --notification-endpoint "$NOTIFICATION_QUEUE_ARN" \
  --query 'SubscriptionArn' --output text > /dev/null
log "  ✓ invoice-events → notification-queue"

# Subscribe invoice-processing-queue to invoice-events
aws_local sns subscribe \
  --topic-arn "$INVOICE_EVENTS_ARN" \
  --protocol sqs \
  --notification-endpoint "$INVOICE_PROCESSING_QUEUE_ARN" \
  --query 'SubscriptionArn' --output text > /dev/null
log "  ✓ invoice-events → invoice-processing-queue"

log "SNS subscriptions created ✓"

# ─── DynamoDB Tables ──────────────────────────────────────────────────────────
log "Creating DynamoDB tables..."

# CarrierRateTable — PK: carrierId, SK: laneId
aws_local dynamodb create-table \
  --table-name "CarrierRateTable-${ENV}" \
  --attribute-definitions \
    AttributeName=carrierId,AttributeType=S \
    AttributeName=laneId,AttributeType=S \
  --key-schema \
    AttributeName=carrierId,KeyType=HASH \
    AttributeName=laneId,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes '[{
    "IndexName": "laneId-carrierId-index",
    "KeySchema": [
      {"AttributeName": "laneId", "KeyType": "HASH"},
      {"AttributeName": "carrierId", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' 2>/dev/null || true
log "  ✓ CarrierRateTable"

# TrackingEventTable — PK: shipmentId, SK: eventTimestamp (TTL: 90 days)
aws_local dynamodb create-table \
  --table-name "TrackingEventTable-${ENV}" \
  --attribute-definitions \
    AttributeName=shipmentId,AttributeType=S \
    AttributeName=eventTimestamp,AttributeType=S \
  --key-schema \
    AttributeName=shipmentId,KeyType=HASH \
    AttributeName=eventTimestamp,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST 2>/dev/null || true

# Enable TTL on TrackingEventTable
aws_local dynamodb update-time-to-live \
  --table-name "TrackingEventTable-${ENV}" \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" 2>/dev/null || true
log "  ✓ TrackingEventTable (with TTL)"

# DocumentIndexTable — PK: documentId
aws_local dynamodb create-table \
  --table-name "DocumentIndexTable-${ENV}" \
  --attribute-definitions \
    AttributeName=documentId,AttributeType=S \
    AttributeName=shipmentId,AttributeType=S \
  --key-schema \
    AttributeName=documentId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes '[{
    "IndexName": "shipmentId-index",
    "KeySchema": [
      {"AttributeName": "shipmentId", "KeyType": "HASH"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' 2>/dev/null || true
log "  ✓ DocumentIndexTable"

log "DynamoDB tables created ✓"

# ─── Secrets Manager ──────────────────────────────────────────────────────────
log "Creating Secrets Manager secrets..."

create_secret() {
  local name="$1"
  local value="$2"
  aws_local secretsmanager create-secret \
    --name "$name" \
    --secret-string "$value" 2>/dev/null || \
  aws_local secretsmanager update-secret \
    --secret-id "$name" \
    --secret-string "$value" 2>/dev/null || true
}

# Database credentials for each service
create_secret "/smartfreight/${ENV}/aurora/shipment" \
  '{"username":"shipment_svc","password":"localpassword","host":"localhost","port":5432,"dbname":"shipment_db"}'
log "  ✓ Aurora shipment-db secret"

create_secret "/smartfreight/${ENV}/aurora/invoice" \
  '{"username":"invoice_svc","password":"localpassword","host":"localhost","port":5432,"dbname":"invoice_db"}'
log "  ✓ Aurora invoice-db secret"

# Carrier API keys (mock values for local dev)
create_secret "/smartfreight/${ENV}/carriers/fedex" \
  '{"apiKey":"FEDEX_LOCAL_DEV_KEY","clientId":"fedex-local","clientSecret":"fedex-local-secret"}'
log "  ✓ FedEx carrier API key"

create_secret "/smartfreight/${ENV}/carriers/ups" \
  '{"apiKey":"UPS_LOCAL_DEV_KEY","clientId":"ups-local","clientSecret":"ups-local-secret"}'
log "  ✓ UPS carrier API key"

# Cognito client (mock for local dev — security disabled locally)
create_secret "/smartfreight/${ENV}/cognito/client" \
  '{"clientId":"local-cognito-client","clientSecret":"local-cognito-secret"}'
log "  ✓ Cognito client secret"

log "Secrets Manager secrets created ✓"

# ─── Seed Sample Data ─────────────────────────────────────────────────────────
log "Seeding sample carrier rate data into DynamoDB..."

# Sample FedEx rates
aws_local dynamodb put-item \
  --table-name "CarrierRateTable-${ENV}" \
  --item '{
    "carrierId": {"S": "fedex"},
    "laneId": {"S": "TX-CA-LTL"},
    "carrierName": {"S": "FedEx Freight"},
    "originState": {"S": "TX"},
    "destinationState": {"S": "CA"},
    "shipmentType": {"S": "LTL"},
    "ratePerCwt": {"N": "12.50"},
    "fuelSurchargePercent": {"N": "18.5"},
    "minimumCharge": {"N": "250.00"},
    "transitDays": {"N": "3"},
    "active": {"BOOL": true}
  }' 2>/dev/null || true

aws_local dynamodb put-item \
  --table-name "CarrierRateTable-${ENV}" \
  --item '{
    "carrierId": {"S": "ups"},
    "laneId": {"S": "TX-CA-LTL"},
    "carrierName": {"S": "UPS Freight"},
    "originState": {"S": "TX"},
    "destinationState": {"S": "CA"},
    "shipmentType": {"S": "LTL"},
    "ratePerCwt": {"N": "11.80"},
    "fuelSurchargePercent": {"N": "17.2"},
    "minimumCharge": {"N": "225.00"},
    "transitDays": {"N": "4"},
    "active": {"BOOL": true}
  }' 2>/dev/null || true

aws_local dynamodb put-item \
  --table-name "CarrierRateTable-${ENV}" \
  --item '{
    "carrierId": {"S": "fedex"},
    "laneId": {"S": "NY-FL-LTL"},
    "carrierName": {"S": "FedEx Freight"},
    "originState": {"S": "NY"},
    "destinationState": {"S": "FL"},
    "shipmentType": {"S": "LTL"},
    "ratePerCwt": {"N": "14.20"},
    "fuelSurchargePercent": {"N": "18.5"},
    "minimumCharge": {"N": "300.00"},
    "transitDays": {"N": "2"},
    "active": {"BOOL": true}
  }' 2>/dev/null || true

log "  ✓ Sample carrier rate data seeded"

# ─── SES Email Identity Verification (LocalStack) ──────────────────────────────
log "Verifying SES email identity..."
aws_local ses verify-email-identity \
  --email-address "noreply@smartfreight.com" 2>/dev/null || true
log "  ✓ SES identity verified: noreply@smartfreight.com"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "✅ LocalStack seed complete!"
echo "============================================================"
echo ""
echo "Environment Variables for services (add to .env or IDE run config):"
echo ""
echo "# AWS"
echo "AWS_ACCESS_KEY_ID=test"
echo "AWS_SECRET_ACCESS_KEY=test"
echo "AWS_REGION=us-east-1"
echo "AWS_ENDPOINT_URL=http://localhost:4566"
echo ""
echo "# Databases"
echo "DATABASE_URL=jdbc:postgresql://localhost:5432/shipment_db"
echo "DATABASE_USERNAME=shipment_svc"
echo "DATABASE_PASSWORD=localpassword"
echo ""
echo "# SNS Topics"
echo "SHIPMENT_EVENTS_TOPIC_ARN=$SHIPMENT_EVENTS_ARN"
echo "INVOICE_EVENTS_TOPIC_ARN=$INVOICE_EVENTS_ARN"
echo "CARRIER_EVENTS_TOPIC_ARN=$CARRIER_EVENTS_ARN"
echo ""
echo "# SQS Queues"
echo "NOTIFICATION_QUEUE_URL=$NOTIFICATION_QUEUE_URL"
echo "INVOICE_PROCESSING_QUEUE_URL=$INVOICE_PROCESSING_QUEUE_URL"
echo "SHIPMENT_INBOUND_QUEUE_URL=$SHIPMENT_INBOUND_QUEUE_URL"
echo ""
echo "# DynamoDB"
echo "CARRIER_RATE_TABLE_NAME=CarrierRateTable-dev"
echo ""
echo "# S3"
echo "DOCUMENTS_BUCKET=smartfreight-documents-dev"
echo ""
echo "# SES"
echo "SES_FROM_ADDRESS=noreply@smartfreight.com"
echo "SES_CONFIG_SET=smartfreight-notifications"
echo ""
echo "LocalStack UI: http://localhost:8080"
echo "============================================================"
