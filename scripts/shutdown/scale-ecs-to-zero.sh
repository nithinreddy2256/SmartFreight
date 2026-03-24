#!/usr/bin/env bash
# =============================================================================
# SmartFreight — Scale ECS Services to Zero (Cost Saving)
# =============================================================================
# Triggered nightly by EventBridge at 20:00 UTC in dev/test environments.
# Scales all ECS services to desired count = 0 to eliminate Fargate charges.
#
# Can also be run manually:
#   ./scale-ecs-to-zero.sh dev
#   ./scale-ecs-to-zero.sh test
#
# To scale back up (morning startup):
#   ./scale-ecs-to-zero.sh dev --up
# =============================================================================
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> [--up|--down]}"
DIRECTION="${2:---down}"

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="smartfreight-${ENVIRONMENT}"

# Minimum desired count when scaling back up (from SSM or default)
DESIRED_UP="${DESIRED_COUNT_UP:-1}"

log()  { echo "[$(date '+%H:%M:%S')] $1"; }
warn() { echo "[$(date '+%H:%M:%S')] WARNING: $1" >&2; }

SERVICES=(
  "shipment-service-${ENVIRONMENT}"
  "carrier-service-${ENVIRONMENT}"
  "invoice-service-${ENVIRONMENT}"
  "document-service-${ENVIRONMENT}"
  "notification-service-${ENVIRONMENT}"
  "analytics-service-${ENVIRONMENT}"
)

scale_service() {
  local SERVICE_NAME="$1"
  local DESIRED_COUNT="$2"

  local CURRENT_COUNT
  CURRENT_COUNT=$(aws ecs describe-services \
    --cluster "${CLUSTER_NAME}" \
    --services "${SERVICE_NAME}" \
    --region "${AWS_REGION}" \
    --query 'services[0].desiredCount' \
    --output text 2>/dev/null || echo "MISSING")

  if [ "${CURRENT_COUNT}" = "MISSING" ] || [ "${CURRENT_COUNT}" = "None" ]; then
    warn "Service not found or not accessible: ${SERVICE_NAME} — skipping"
    return 0
  fi

  if [ "${CURRENT_COUNT}" = "${DESIRED_COUNT}" ]; then
    log "  Already at ${DESIRED_COUNT} — skipping: ${SERVICE_NAME}"
    return 0
  fi

  aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --desired-count "${DESIRED_COUNT}" \
    --region "${AWS_REGION}" \
    --query 'service.serviceName' \
    --output text > /dev/null

  log "  ✓ ${SERVICE_NAME}: ${CURRENT_COUNT} → ${DESIRED_COUNT}"
}

# Guard: never scale down production
if [ "${ENVIRONMENT}" = "prod" ] && [ "${DIRECTION}" = "--down" ]; then
  echo "ERROR: Refusing to scale down production environment." >&2
  echo "If you really mean this, set ALLOW_PROD_SCALE_DOWN=true" >&2
  [ "${ALLOW_PROD_SCALE_DOWN:-false}" = "true" ] || exit 1
fi

case "${DIRECTION}" in
  --down)
    log "Scaling down all ECS services in cluster: ${CLUSTER_NAME}"
    for svc in "${SERVICES[@]}"; do
      scale_service "${svc}" 0
    done
    log ""
    log "✓ All services scaled to 0. Estimated savings: ~\$3-8/night (Fargate)"
    log "  To scale back up: $0 ${ENVIRONMENT} --up"
    ;;

  --up)
    log "Scaling up all ECS services in cluster: ${CLUSTER_NAME} (desired=${DESIRED_UP})"
    for svc in "${SERVICES[@]}"; do
      scale_service "${svc}" "${DESIRED_UP}"
    done

    # Wait for all services to reach stable state
    log "Waiting for services to stabilize..."
    aws ecs wait services-stable \
      --cluster "${CLUSTER_NAME}" \
      --services "${SERVICES[@]}" \
      --region "${AWS_REGION}" 2>/dev/null || \
    log "Note: Some services may still be starting. Check ECS console."

    log "✓ All services scaled to ${DESIRED_UP} task(s)"
    ;;

  *)
    echo "ERROR: Unknown direction '${DIRECTION}'. Use --up or --down." >&2
    exit 1
    ;;
esac
