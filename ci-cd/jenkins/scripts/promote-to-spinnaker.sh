#!/usr/bin/env bash
# =============================================================================
# SmartFreight — promote-to-spinnaker.sh
#
# Triggers a Spinnaker deployment pipeline via the Gate API.
# Waits for the pipeline execution to start, then returns the execution ID.
#
# Usage:
#   ./promote-to-spinnaker.sh \
#       <SERVICE_NAME> \
#       <ENVIRONMENT> \
#       <IMAGE_URI> \
#       [SPINNAKER_GATE_URL] \
#       [SPINNAKER_API_TOKEN]
#
# Arguments:
#   SERVICE_NAME        e.g. shipment-service
#   ENVIRONMENT         dev | test | prod
#   IMAGE_URI           Full ECR image URI with tag
#   SPINNAKER_GATE_URL  Base URL of Spinnaker Gate API (default: http://spinnaker-gate:8084)
#   SPINNAKER_API_TOKEN Bearer token for Spinnaker Gate authentication (optional)
#
# Output:
#   Prints the Spinnaker pipeline execution ID to stdout on success.
#   All diagnostic output goes to stderr so stdout remains clean for capture.
#
# Exit codes:
#   0  — Pipeline triggered successfully; execution ID printed to stdout
#   1  — Missing arguments, API error, or timeout waiting for execution
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[promote-to-spinnaker] $*" >&2; }
err()  { echo "[promote-to-spinnaker] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 3 ]]; then
    die "Usage: $0 <SERVICE_NAME> <ENVIRONMENT> <IMAGE_URI> [SPINNAKER_GATE_URL] [SPINNAKER_API_TOKEN]"
fi

SERVICE_NAME="${1}"
ENVIRONMENT="${2}"
IMAGE_URI="${3}"
GATE_URL="${4:-${SPINNAKER_GATE_URL:-http://spinnaker-gate:8084}}"
API_TOKEN="${5:-${SPINNAKER_API_TOKEN:-}}"

# Validate ENVIRONMENT
case "${ENVIRONMENT}" in
    dev|test|prod) ;;
    *) die "ENVIRONMENT must be one of: dev, test, prod. Got: '${ENVIRONMENT}'" ;;
esac

# Derive Spinnaker application and pipeline names from service name
# Convention: service 'shipment-service' → app 'smartfreight', pipeline 'shipment-service-pipeline'
SPINNAKER_APP="smartfreight"
PIPELINE_NAME="${SERVICE_NAME}-pipeline"

# Poll configuration
MAX_WAIT_SECONDS=120        # Maximum seconds to wait for execution to appear
POLL_INTERVAL_SECONDS=5     # Seconds between poll attempts
MAX_ATTEMPTS=$(( MAX_WAIT_SECONDS / POLL_INTERVAL_SECONDS ))

log "Service      : ${SERVICE_NAME}"
log "Environment  : ${ENVIRONMENT}"
log "Image URI    : ${IMAGE_URI}"
log "Gate URL     : ${GATE_URL}"
log "Spinnaker App: ${SPINNAKER_APP}"
log "Pipeline     : ${PIPELINE_NAME}"

# ---------------------------------------------------------------------------
# Build curl auth header
# ---------------------------------------------------------------------------
AUTH_HEADER=""
if [[ -n "${API_TOKEN}" ]]; then
    AUTH_HEADER="Authorization: Bearer ${API_TOKEN}"
fi

curl_cmd() {
    local args=("$@")
    if [[ -n "${AUTH_HEADER}" ]]; then
        curl --silent --show-error --fail \
             --max-time 30 \
             -H "${AUTH_HEADER}" \
             "${args[@]}"
    else
        curl --silent --show-error --fail \
             --max-time 30 \
             "${args[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Verify Gate API is reachable
# ---------------------------------------------------------------------------
log "Checking Spinnaker Gate connectivity at ${GATE_URL}/health ..."

GATE_HEALTH=""
for attempt in $(seq 1 5); do
    GATE_HEALTH=$(curl_cmd "${GATE_URL}/health" 2>/dev/null || true)
    if echo "${GATE_HEALTH}" | grep -q '"status":"UP"' 2>/dev/null; then
        log "Gate API is healthy."
        break
    fi
    log "Gate health check attempt ${attempt}/5 failed, retrying in 10s ..."
    sleep 10
done

if ! echo "${GATE_HEALTH}" | grep -q '"status":"UP"' 2>/dev/null; then
    die "Spinnaker Gate API is not reachable or unhealthy at ${GATE_URL}/health"
fi

# ---------------------------------------------------------------------------
# Step 2: Verify the pipeline exists before triggering
# ---------------------------------------------------------------------------
log "Verifying pipeline '${PIPELINE_NAME}' exists in application '${SPINNAKER_APP}' ..."

PIPELINE_RESPONSE=$(curl_cmd \
    "${GATE_URL}/applications/${SPINNAKER_APP}/pipelineConfigs/${PIPELINE_NAME}" \
    2>/dev/null) || die "Pipeline '${PIPELINE_NAME}' not found in application '${SPINNAKER_APP}'"

log "Pipeline found."

# ---------------------------------------------------------------------------
# Step 3: Build the trigger payload
# ---------------------------------------------------------------------------
BUILD_NUMBER="${BUILD_NUMBER:-0}"
GIT_COMMIT_SHA="${GIT_COMMIT_SHA:-$(echo "${IMAGE_URI}" | grep -oE '[a-f0-9]{12}$' || echo 'unknown')}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Spinnaker manual pipeline trigger payload.
# The 'parameters' map is passed to the pipeline as execution parameters.
# The 'artifacts' list provides the Docker image artifact for manifest baking.
TRIGGER_PAYLOAD=$(cat <<EOF
{
  "type": "manual",
  "dryRun": false,
  "user": "jenkins-ci",
  "parameters": {
    "serviceName": "${SERVICE_NAME}",
    "environment": "${ENVIRONMENT}",
    "imageUri": "${IMAGE_URI}",
    "gitSha": "${GIT_COMMIT_SHA}",
    "buildNumber": "${BUILD_NUMBER}",
    "triggeredAt": "${TIMESTAMP}"
  },
  "artifacts": [
    {
      "type": "docker/image",
      "name": "$(echo "${IMAGE_URI}" | cut -d: -f1)",
      "version": "$(echo "${IMAGE_URI}" | cut -d: -f2)",
      "reference": "${IMAGE_URI}"
    }
  ]
}
EOF
)

log "Trigger payload prepared."

# ---------------------------------------------------------------------------
# Step 4: POST to Gate to trigger the pipeline
# ---------------------------------------------------------------------------
log "Triggering pipeline via POST to ${GATE_URL}/pipelines/${SPINNAKER_APP}/${PIPELINE_NAME} ..."

TRIGGER_RESPONSE=$(curl_cmd \
    -X POST \
    -H "Content-Type: application/json" \
    -d "${TRIGGER_PAYLOAD}" \
    "${GATE_URL}/pipelines/${SPINNAKER_APP}/${PIPELINE_NAME}") \
    || die "Failed to POST trigger to Spinnaker Gate API."

log "Trigger response: ${TRIGGER_RESPONSE}"

# Gate returns a task reference on success, e.g.:
# {"ref": "/tasks/01ABCD..."}
TASK_REF=$(echo "${TRIGGER_RESPONSE}" | jq -r '.ref // empty' 2>/dev/null || true)

if [[ -z "${TASK_REF}" ]]; then
    # Some Gate versions return the execution ID directly
    EXEC_ID=$(echo "${TRIGGER_RESPONSE}" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -n "${EXEC_ID}" ]]; then
        log "Pipeline execution started immediately. Execution ID: ${EXEC_ID}"
        echo "${EXEC_ID}"
        exit 0
    fi
    die "No task ref or execution ID found in Gate response: ${TRIGGER_RESPONSE}"
fi

log "Task ref returned by Gate: ${TASK_REF}"

# ---------------------------------------------------------------------------
# Step 5: Poll the task until the pipeline execution ID is available
# ---------------------------------------------------------------------------
log "Polling task ${TASK_REF} for pipeline execution ID (max ${MAX_WAIT_SECONDS}s) ..."

TASK_ID=$(basename "${TASK_REF}")
EXEC_ID=""

for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    TASK_STATUS=$(curl_cmd \
        "${GATE_URL}/tasks/${TASK_ID}" 2>/dev/null) || {
        log "Poll attempt ${attempt}: task endpoint unreachable, retrying ..."
        sleep "${POLL_INTERVAL_SECONDS}"
        continue
    }

    TASK_STATE=$(echo "${TASK_STATUS}" | jq -r '.status // empty' 2>/dev/null || true)
    log "Poll attempt ${attempt}/${MAX_ATTEMPTS}: task state = ${TASK_STATE}"

    # Extract execution ID from task result variables
    EXEC_ID=$(echo "${TASK_STATUS}" \
        | jq -r '.resultObjects[]?.id // empty' 2>/dev/null | head -1 || true)

    # Also check inside execution.id if resultObjects is absent
    if [[ -z "${EXEC_ID}" ]]; then
        EXEC_ID=$(echo "${TASK_STATUS}" \
            | jq -r '.variables[] | select(.key=="pipelineExecutionId") | .value // empty' \
            2>/dev/null || true)
    fi

    if [[ -n "${EXEC_ID}" ]]; then
        log "Pipeline execution ID obtained: ${EXEC_ID}"
        break
    fi

    case "${TASK_STATE}" in
        SUCCEEDED)
            # Execution may have been embedded in a different field
            EXEC_ID=$(echo "${TASK_STATUS}" \
                | jq -r '.. | .executionId? // empty' 2>/dev/null | head -1 || true)
            if [[ -n "${EXEC_ID}" ]]; then
                log "Execution ID from SUCCEEDED task: ${EXEC_ID}"
                break
            fi
            # Task succeeded but we cannot find the exec ID; fabricate from timestamp
            EXEC_ID="UNKNOWN-$(date +%s)"
            log "WARN: Task SUCCEEDED but execution ID not found. Using fallback: ${EXEC_ID}"
            break
            ;;
        TERMINAL|FAILED)
            die "Spinnaker task ${TASK_ID} reached terminal state '${TASK_STATE}' before pipeline execution started."
            ;;
    esac

    sleep "${POLL_INTERVAL_SECONDS}"
done

if [[ -z "${EXEC_ID}" ]]; then
    die "Timed out after ${MAX_WAIT_SECONDS}s waiting for Spinnaker pipeline execution ID."
fi

# ---------------------------------------------------------------------------
# Step 6: Log the Spinnaker UI link for convenience
# ---------------------------------------------------------------------------
GATE_HOST=$(echo "${GATE_URL}" | sed 's|http[s]*://||' | cut -d: -f1)
log "Spinnaker UI: http://${GATE_HOST}:9000/#/applications/${SPINNAKER_APP}/executions/details/${EXEC_ID}"
log "Pipeline execution ID: ${EXEC_ID}"

# ---------------------------------------------------------------------------
# Output ONLY the execution ID to stdout (captured by Jenkins)
# ---------------------------------------------------------------------------
echo "${EXEC_ID}"
