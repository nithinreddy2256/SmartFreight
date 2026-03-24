#!/usr/bin/env bash
# =============================================================================
# SmartFreight — ECS Service Rollback Script
# =============================================================================
# Triggers a Spinnaker rollback OR directly rolls back ECS to the previous
# stable task definition revision.
#
# Usage:
#   ./rollback.sh <service-name> <environment> [--spinnaker | --direct]
#   ./rollback.sh shipment-service prod --spinnaker
#   ./rollback.sh shipment-service dev --direct
# =============================================================================
set -euo pipefail

SERVICE_NAME="${1:?Usage: $0 <service-name> <environment> [--spinnaker|--direct]}"
ENVIRONMENT="${2:?Usage: $0 <service-name> <environment> [--spinnaker|--direct]}"
MODE="${3:---direct}"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="smartfreight-${ENVIRONMENT}"
ECS_SERVICE_NAME="${SERVICE_NAME}-${ENVIRONMENT}"
SPINNAKER_GATE_URL="${SPINNAKER_GATE_URL:-http://localhost:8084}"
SPINNAKER_TOKEN="${SPINNAKER_TOKEN:-}"

log()  { echo "[$(date '+%H:%M:%S')] $1"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2; }
err()  { echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2; exit 1; }

log "Starting rollback: service=${SERVICE_NAME} env=${ENVIRONMENT} mode=${MODE}"

# ─── Spinnaker rollback ───────────────────────────────────────────────────────
spinnaker_rollback() {
  local APP="smartfreight"
  local PIPELINE="${SERVICE_NAME}-rollback"
  local PAYLOAD
  PAYLOAD=$(jq -nc \
    --arg svc "${SERVICE_NAME}" \
    --arg env "${ENVIRONMENT}" \
    '{"parameters": {"serviceName": $svc, "environment": $env, "rollbackSteps": "1"}}')

  log "Triggering Spinnaker rollback pipeline: ${PIPELINE}"
  local AUTH_HEADER=""
  [ -n "${SPINNAKER_TOKEN}" ] && AUTH_HEADER="-H 'Authorization: Bearer ${SPINNAKER_TOKEN}'"

  local RESPONSE
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${SPINNAKER_GATE_URL}/pipelines/${APP}/${PIPELINE}" \
    -H "Content-Type: application/json" \
    ${AUTH_HEADER} \
    -d "${PAYLOAD}")

  local HTTP_CODE
  HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
  local BODY
  BODY=$(echo "${RESPONSE}" | head -n -1)

  if [ "${HTTP_CODE}" -ne 200 ] && [ "${HTTP_CODE}" -ne 202 ]; then
    err "Spinnaker rollback failed (HTTP ${HTTP_CODE}): ${BODY}"
  fi

  local EXEC_ID
  EXEC_ID=$(echo "${BODY}" | jq -r '.ref // .id // "unknown"')
  log "✓ Spinnaker rollback triggered. executionId=${EXEC_ID}"
  echo "${EXEC_ID}"
}

# ─── Direct ECS rollback ─────────────────────────────────────────────────────
direct_rollback() {
  log "Fetching current task definition for service=${ECS_SERVICE_NAME}"

  # Get current task definition ARN
  local CURRENT_TASK_DEF
  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "${CLUSTER_NAME}" \
    --services "${ECS_SERVICE_NAME}" \
    --region "${AWS_REGION}" \
    --query 'services[0].taskDefinition' \
    --output text)

  if [ -z "${CURRENT_TASK_DEF}" ] || [ "${CURRENT_TASK_DEF}" = "None" ]; then
    err "Service not found: cluster=${CLUSTER_NAME} service=${ECS_SERVICE_NAME}"
  fi

  log "Current task definition: ${CURRENT_TASK_DEF}"

  # Parse family and revision
  # ARN format: arn:aws:ecs:region:account:task-definition/family:revision
  local FAMILY
  FAMILY=$(echo "${CURRENT_TASK_DEF}" | sed 's/.*task-definition\///' | cut -d: -f1)
  local CURRENT_REV
  CURRENT_REV=$(echo "${CURRENT_TASK_DEF}" | cut -d: -f2)

  if [ "${CURRENT_REV}" -le 1 ]; then
    err "Already at revision 1 — cannot roll back further."
  fi

  local PREV_REV=$((CURRENT_REV - 1))
  local PREV_TASK_DEF="${FAMILY}:${PREV_REV}"

  log "Rolling back from revision ${CURRENT_REV} to ${PREV_REV}"

  # Verify previous revision exists and is ACTIVE
  local PREV_STATUS
  PREV_STATUS=$(aws ecs describe-task-definition \
    --task-definition "${PREV_TASK_DEF}" \
    --region "${AWS_REGION}" \
    --query 'taskDefinition.status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

  if [ "${PREV_STATUS}" != "ACTIVE" ]; then
    err "Previous task definition ${PREV_TASK_DEF} is not ACTIVE (status: ${PREV_STATUS})"
  fi

  # Update ECS service to use previous task definition
  log "Updating ECS service to use ${PREV_TASK_DEF}..."
  aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${ECS_SERVICE_NAME}" \
    --task-definition "${PREV_TASK_DEF}" \
    --region "${AWS_REGION}" \
    --query 'service.serviceArn' \
    --output text

  log "Waiting for service to stabilize..."
  aws ecs wait services-stable \
    --cluster "${CLUSTER_NAME}" \
    --services "${ECS_SERVICE_NAME}" \
    --region "${AWS_REGION}"

  log "✓ Rollback complete: ${FAMILY} ${CURRENT_REV} → ${PREV_REV}"

  # Tag the event in CloudWatch for audit trail
  aws cloudwatch put-metric-data \
    --namespace "SmartFreight/Deployments" \
    --metric-data "[{
      \"MetricName\": \"Rollback\",
      \"Dimensions\": [
        {\"Name\": \"Service\", \"Value\": \"${SERVICE_NAME}\"},
        {\"Name\": \"Environment\", \"Value\": \"${ENVIRONMENT}\"}
      ],
      \"Value\": 1,
      \"Unit\": \"Count\"
    }]" \
    --region "${AWS_REGION}" 2>/dev/null || true
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "${MODE}" in
  --spinnaker) spinnaker_rollback ;;
  --direct)    direct_rollback ;;
  *) err "Unknown mode: ${MODE}. Use --spinnaker or --direct" ;;
esac
