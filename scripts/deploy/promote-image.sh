#!/usr/bin/env bash
# =============================================================================
# SmartFreight — ECR Image Promotion Script
# =============================================================================
# Tags an ECR image for environment promotion without rebuilding.
# Used by Jenkins Stage 8 and Spinnaker promote stages.
#
# Usage:
#   ./promote-image.sh <service-name> <source-tag> <target-env>
#   ./promote-image.sh shipment-service abc123f dev
#   ./promote-image.sh shipment-service abc123f test
# =============================================================================
set -euo pipefail

SERVICE_NAME="${1:?Usage: $0 <service-name> <source-tag> <target-env>}"
SOURCE_TAG="${2:?Usage: $0 <service-name> <source-tag> <target-env>}"
TARGET_ENV="${3:?Usage: $0 <service-name> <source-tag> <target-env>}"

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REGISTRY="${ECR_REGISTRY:-$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com}"
REPO="${ECR_REGISTRY}/smartfreight/${SERVICE_NAME}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Promoting image: service=${SERVICE_NAME} from=${SOURCE_TAG} to=${TARGET_ENV}"

# Authenticate to ECR
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Get the image manifest from source tag
log "Fetching manifest for tag=${SOURCE_TAG}"
MANIFEST=$(aws ecr batch-get-image \
  --repository-name "smartfreight/${SERVICE_NAME}" \
  --image-ids imageTag="${SOURCE_TAG}" \
  --region "${AWS_REGION}" \
  --query 'images[0].imageManifest' \
  --output text)

if [ -z "${MANIFEST}" ] || [ "${MANIFEST}" = "None" ]; then
  echo "ERROR: Image not found: ${REPO}:${SOURCE_TAG}" >&2
  exit 1
fi

# Re-tag image to target environment tag
TARGET_TAG="${TARGET_ENV}-latest"
log "Tagging: ${SOURCE_TAG} → ${TARGET_TAG}"

aws ecr put-image \
  --repository-name "smartfreight/${SERVICE_NAME}" \
  --image-tag "${TARGET_TAG}" \
  --image-manifest "${MANIFEST}" \
  --region "${AWS_REGION}" || true  # Ignore error if tag already exists with same manifest

# Also tag with env-specific timestamp for rollback capability
TIMESTAMP_TAG="${TARGET_ENV}-$(date '+%Y%m%d-%H%M%S')"
aws ecr put-image \
  --repository-name "smartfreight/${SERVICE_NAME}" \
  --image-tag "${TIMESTAMP_TAG}" \
  --image-manifest "${MANIFEST}" \
  --region "${AWS_REGION}" || true

# Update deploy/image-tag.json
IMAGE_TAG_FILE="$(git rev-parse --show-toplevel 2>/dev/null || echo '.')/deploy/image-tag.json"
if [ -f "${IMAGE_TAG_FILE}" ]; then
  FULL_IMAGE_URI="${REPO}:${SOURCE_TAG}"
  jq --arg svc "${SERVICE_NAME}" \
     --arg env "${TARGET_ENV}" \
     --arg uri "${FULL_IMAGE_URI}" \
     --arg tag "${SOURCE_TAG}" \
     '.[$svc][$env] = {"imageUri": $uri, "imageTag": $tag, "promotedAt": (now | todate)}' \
     "${IMAGE_TAG_FILE}" > "${IMAGE_TAG_FILE}.tmp" && mv "${IMAGE_TAG_FILE}.tmp" "${IMAGE_TAG_FILE}"
  log "Updated deploy/image-tag.json"
fi

log "✓ Promotion complete: ${REPO}:${SOURCE_TAG} → ${TARGET_TAG}, ${TIMESTAMP_TAG}"
echo "${REPO}:${SOURCE_TAG}"
