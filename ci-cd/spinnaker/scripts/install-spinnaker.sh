#!/usr/bin/env bash
# =============================================================================
# SmartFreight — install-spinnaker.sh
#
# Installs and configures Spinnaker using Halyard with:
#   - ECS cloud provider (us-east-1)
#   - ECR artifact account
#   - Jenkins CI integration
#   - S3 storage backend for Spinnaker config/pipelines
#   - Distributed deployment on ECS (or local for dev)
#
# Prerequisites:
#   - Ubuntu 20.04/22.04 or Amazon Linux 2 (runs as sudo-capable user)
#   - AWS credentials with permissions to create ECS tasks, S3 access, ECR access
#   - Java 11+ on the host (Halyard requirement)
#   - curl, jq, unzip
#
# Usage:
#   sudo ./install-spinnaker.sh [OPTIONS]
#
# Options:
#   --account-id ID          AWS account ID (required)
#   --region REGION          AWS region (default: us-east-1)
#   --s3-bucket BUCKET       S3 bucket for Spinnaker storage (required)
#   --ecs-cluster CLUSTER    ECS cluster ARN for distributed deployment
#   --jenkins-url URL        Jenkins base URL (e.g. http://jenkins:8080)
#   --jenkins-user USER      Jenkins API user (default: spinnaker)
#   --jenkins-token TOKEN    Jenkins API token
#   --ecr-registry URL       ECR registry URL (ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com)
#   --spinnaker-version VER  Spinnaker version (default: 1.33.0)
#   --halyard-version VER    Halyard version (default: 1.12.2)
#   --deployment-type TYPE   'local' for dev | 'distributed' for ECS (default: local)
#   --slack-token TOKEN      Slack bot token for pipeline notifications
#   --dry-run                Print Halyard commands; do not execute them
#   -h, --help               Show this help text
#
# Exit codes:
#   0  — Installation and configuration complete
#   1  — Fatal error
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AWS_ACCOUNT_ID=""
AWS_REGION="us-east-1"
S3_BUCKET=""
ECS_CLUSTER=""
JENKINS_URL=""
JENKINS_USER="spinnaker"
JENKINS_TOKEN=""
ECR_REGISTRY=""
SPINNAKER_VERSION="1.33.0"
HALYARD_VERSION="1.12.2"
DEPLOYMENT_TYPE="local"
SLACK_TOKEN=""
DRY_RUN=false

HALYARD_HOME="${HOME}/.hal"
HALYARD_USER="${SUDO_USER:-$(whoami)}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[install-spinnaker] $*"; }
warn() { echo "[install-spinnaker] WARN: $*" >&2; }
err()  { echo "[install-spinnaker] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

hal_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "[install-spinnaker] DRY hal $*"
    else
        hal "$@"
    fi
}

usage() {
    grep '^#' "${BASH_SOURCE[0]}" | grep -v '^#!' | sed 's/^# \{0,1\}//'
    exit 0
}

require_cmd() {
    command -v "${1}" &>/dev/null || die "Required command not found: ${1}. Please install it before running this script."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "${1}" in
        --account-id)       AWS_ACCOUNT_ID="${2}"; shift 2 ;;
        --region)           AWS_REGION="${2}"; shift 2 ;;
        --s3-bucket)        S3_BUCKET="${2}"; shift 2 ;;
        --ecs-cluster)      ECS_CLUSTER="${2}"; shift 2 ;;
        --jenkins-url)      JENKINS_URL="${2}"; shift 2 ;;
        --jenkins-user)     JENKINS_USER="${2}"; shift 2 ;;
        --jenkins-token)    JENKINS_TOKEN="${2}"; shift 2 ;;
        --ecr-registry)     ECR_REGISTRY="${2}"; shift 2 ;;
        --spinnaker-version) SPINNAKER_VERSION="${2}"; shift 2 ;;
        --halyard-version)  HALYARD_VERSION="${2}"; shift 2 ;;
        --deployment-type)  DEPLOYMENT_TYPE="${2}"; shift 2 ;;
        --slack-token)      SLACK_TOKEN="${2}"; shift 2 ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -h|--help)          usage ;;
        *) die "Unknown argument: ${1}. Run with --help for usage." ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required arguments
# ---------------------------------------------------------------------------
[[ -n "${AWS_ACCOUNT_ID}" ]] || die "--account-id is required."
[[ -n "${S3_BUCKET}" ]]      || die "--s3-bucket is required."

# Derive ECR registry from account ID and region if not provided
if [[ -z "${ECR_REGISTRY}" ]]; then
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

log "==================================================================="
log "SmartFreight Spinnaker Installation"
log "==================================================================="
log "AWS Account ID   : ${AWS_ACCOUNT_ID}"
log "AWS Region       : ${AWS_REGION}"
log "S3 Bucket        : ${S3_BUCKET}"
log "ECS Cluster      : ${ECS_CLUSTER:-<not set — local deployment>}"
log "ECR Registry     : ${ECR_REGISTRY}"
log "Jenkins URL      : ${JENKINS_URL:-<not set>}"
log "Spinnaker version: ${SPINNAKER_VERSION}"
log "Halyard version  : ${HALYARD_VERSION}"
log "Deployment type  : ${DEPLOYMENT_TYPE}"
log "Dry run          : ${DRY_RUN}"
log "==================================================================="

# ---------------------------------------------------------------------------
# Phase 1: Install prerequisites
# ---------------------------------------------------------------------------
log "Phase 1: Checking prerequisites ..."

require_cmd curl
require_cmd jq
require_cmd aws

# Check Java (Halyard requires Java 11+)
if command -v java &>/dev/null; then
    JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    log "Java version: ${JAVA_VER}"
    if (( JAVA_VER < 11 )); then
        warn "Java 11+ is required for Halyard. Found Java ${JAVA_VER}."
        warn "Attempting to install OpenJDK 11 ..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq openjdk-11-jdk
        elif command -v yum &>/dev/null; then
            yum install -y java-11-amazon-corretto
        else
            die "Cannot install Java automatically. Please install Java 11+ and re-run."
        fi
    fi
else
    log "Java not found. Installing OpenJDK 11 ..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq openjdk-11-jdk
    elif command -v yum &>/dev/null; then
        yum install -y java-11-amazon-corretto
    else
        die "Cannot install Java automatically. Please install Java 11+ and re-run."
    fi
fi

# ---------------------------------------------------------------------------
# Phase 2: Install Halyard
# ---------------------------------------------------------------------------
log "Phase 2: Installing Halyard ${HALYARD_VERSION} ..."

if command -v hal &>/dev/null; then
    INSTALLED_HAL=$(hal --version 2>/dev/null | head -1 || echo "unknown")
    log "Halyard already installed: ${INSTALLED_HAL}"
    log "Skipping Halyard installation."
else
    HALYARD_INSTALL_URL="https://raw.githubusercontent.com/spinnaker/halyard/master/install/debian/InstallHalyard.sh"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY: Would download and run Halyard installer from ${HALYARD_INSTALL_URL}"
    else
        log "Downloading Halyard installer ..."
        curl -fsSL "${HALYARD_INSTALL_URL}" -o /tmp/InstallHalyard.sh
        chmod +x /tmp/InstallHalyard.sh

        log "Running Halyard installer (version ${HALYARD_VERSION}) ..."
        bash /tmp/InstallHalyard.sh \
            --version "${HALYARD_VERSION}" \
            --user "${HALYARD_USER}" \
            -y

        rm -f /tmp/InstallHalyard.sh

        # Source hal into current PATH
        export PATH="${PATH}:/usr/local/bin"

        hal --version || die "Halyard installation failed."
        log "Halyard installed successfully."
    fi
fi

# ---------------------------------------------------------------------------
# Phase 3: Set Spinnaker version
# ---------------------------------------------------------------------------
log "Phase 3: Setting Spinnaker version to ${SPINNAKER_VERSION} ..."
hal_cmd config version edit --version "${SPINNAKER_VERSION}"

# ---------------------------------------------------------------------------
# Phase 4: Configure storage backend — S3
# ---------------------------------------------------------------------------
log "Phase 4: Configuring S3 storage backend ..."

# Create S3 bucket if it does not exist
if [[ "${DRY_RUN}" != "true" ]]; then
    if ! aws s3api head-bucket --bucket "${S3_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
        log "Creating S3 bucket: ${S3_BUCKET} ..."
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            # us-east-1 does NOT accept --create-bucket-configuration
            aws s3api create-bucket \
                --bucket "${S3_BUCKET}" \
                --region "${AWS_REGION}"
        else
            aws s3api create-bucket \
                --bucket "${S3_BUCKET}" \
                --region "${AWS_REGION}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        # Enable versioning for configuration safety
        aws s3api put-bucket-versioning \
            --bucket "${S3_BUCKET}" \
            --versioning-configuration Status=Enabled
        # Block all public access
        aws s3api put-public-access-block \
            --bucket "${S3_BUCKET}" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        log "S3 bucket created and secured: ${S3_BUCKET}"
    else
        log "S3 bucket already exists: ${S3_BUCKET}"
    fi
fi

hal_cmd config storage s3 edit \
    --bucket "${S3_BUCKET}" \
    --region "${AWS_REGION}" \
    --no-validate

hal_cmd config storage edit --type s3

# ---------------------------------------------------------------------------
# Phase 5: Configure ECS cloud provider
# ---------------------------------------------------------------------------
log "Phase 5: Configuring ECS cloud provider ..."

# ECS provider — enable it
hal_cmd config provider ecs enable

# Add an ECS account named 'smartfreight-aws-dev' pointing to us-east-1.
# The service account / task role will supply credentials at runtime.
for ENV_ACCT in dev test prod; do
    hal_cmd config provider ecs account add "smartfreight-aws-${ENV_ACCT}" \
        --aws-account "smartfreight-aws-${ENV_ACCT}" \
        || warn "ECS account 'smartfreight-aws-${ENV_ACCT}' may already exist."
done

# Configure the AWS provider that ECS builds on
hal_cmd config provider aws enable

for ENV_ACCT in dev test prod; do
    hal_cmd config provider aws account add "smartfreight-aws-${ENV_ACCT}" \
        --account-id "${AWS_ACCOUNT_ID}" \
        --assume-role "role/SpinnakerManagedRole" \
        --regions "${AWS_REGION}" \
        || warn "AWS account 'smartfreight-aws-${ENV_ACCT}' may already exist."
done

# ---------------------------------------------------------------------------
# Phase 6: Configure ECR artifact account
# ---------------------------------------------------------------------------
log "Phase 6: Configuring ECR artifact account ..."

hal_cmd config artifact docker-registry enable

# Add ECR as a Docker registry provider
hal_cmd config provider docker-registry enable

hal_cmd config provider docker-registry account add smartfreight-ecr \
    --address "${ECR_REGISTRY}" \
    --username "AWS" \
    --password-command "aws ecr get-login-password --region ${AWS_REGION}" \
    --repositories \
        "smartfreight/shipment-service" \
        "smartfreight/carrier-service" \
        "smartfreight/invoice-service" \
        "smartfreight/document-service" \
        "smartfreight/notification-service" \
        "smartfreight/analytics-service" \
    || warn "Docker registry account 'smartfreight-ecr' may already exist."

# ---------------------------------------------------------------------------
# Phase 7: Configure Jenkins CI integration
# ---------------------------------------------------------------------------
if [[ -n "${JENKINS_URL}" ]]; then
    log "Phase 7: Configuring Jenkins CI integration ..."

    if [[ -z "${JENKINS_TOKEN}" ]]; then
        warn "No Jenkins API token provided (--jenkins-token). Jenkins integration will be configured but may not authenticate."
    fi

    hal_cmd config ci jenkins enable

    hal_cmd config ci jenkins master add smartfreight-jenkins \
        --address "${JENKINS_URL}" \
        --username "${JENKINS_USER}" \
        --password "${JENKINS_TOKEN:-}" \
        || warn "Jenkins master 'smartfreight-jenkins' may already exist."
else
    log "Phase 7: Skipping Jenkins integration (--jenkins-url not provided)."
fi

# ---------------------------------------------------------------------------
# Phase 8: Configure Slack notifications
# ---------------------------------------------------------------------------
if [[ -n "${SLACK_TOKEN}" ]]; then
    log "Phase 8: Configuring Slack notifications ..."
    hal_cmd config notification slack enable
    hal_cmd config notification slack edit \
        --bot-name "SmartFreight-Spinnaker" \
        --token "${SLACK_TOKEN}"
else
    log "Phase 8: Skipping Slack configuration (--slack-token not provided)."
fi

# ---------------------------------------------------------------------------
# Phase 9: Set deployment type
# ---------------------------------------------------------------------------
log "Phase 9: Configuring deployment type: ${DEPLOYMENT_TYPE} ..."

case "${DEPLOYMENT_TYPE}" in
    local)
        hal_cmd config deploy edit --type localdebian
        log "Configured for local deployment (suitable for development/testing on a single VM)."
        ;;
    distributed)
        if [[ -z "${ECS_CLUSTER}" ]]; then
            die "--ecs-cluster is required when --deployment-type is 'distributed'."
        fi

        # For distributed deployment on ECS, Spinnaker uses the 'clouddriver'
        # account to deploy its own microservices.
        hal_cmd config deploy edit \
            --type distributed \
            --account-name "smartfreight-aws-dev"

        log "Configured for distributed ECS deployment on cluster: ${ECS_CLUSTER}"
        ;;
    *)
        die "Invalid deployment type: '${DEPLOYMENT_TYPE}'. Must be 'local' or 'distributed'."
        ;;
esac

# ---------------------------------------------------------------------------
# Phase 10: Security — configure CORS and basic auth (adjust for your SSO)
# ---------------------------------------------------------------------------
log "Phase 10: Configuring security settings ..."

# Enable UI with the Gate URL as the API endpoint
hal_cmd config security ui edit \
    --override-base-url "http://localhost:9000"

hal_cmd config security api edit \
    --override-base-url "http://localhost:8084"

# Note: For production, configure X.509, SAML, or OAuth2 here.
# Example for OAuth2 (uncomment and customise):
# hal_cmd config security authn oauth2 edit \
#     --provider github \
#     --client-id YOUR_CLIENT_ID \
#     --client-secret YOUR_CLIENT_SECRET \
#     --scope "read:org"
# hal_cmd config security authn oauth2 enable

# ---------------------------------------------------------------------------
# Phase 11: Configure Canary (Kayenta) — CloudWatch metrics
# ---------------------------------------------------------------------------
log "Phase 11: Configuring Kayenta canary analysis ..."

hal_cmd config canary enable

hal_cmd config canary edit \
    --default-metrics-account cloudwatch-prod \
    --default-storage-account s3-spinnaker \
    --default-judge NetflixACAJudge-v1.0

hal_cmd config canary aws enable

hal_cmd config canary aws account add cloudwatch-prod \
    --bucket "${S3_BUCKET}" \
    --region "${AWS_REGION}" \
    || warn "Canary AWS account 'cloudwatch-prod' may already exist."

hal_cmd config canary google disable 2>/dev/null || true
hal_cmd config canary prometheus disable 2>/dev/null || true

# ---------------------------------------------------------------------------
# Phase 12: Validate Halyard configuration
# ---------------------------------------------------------------------------
log "Phase 12: Validating Halyard configuration ..."

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY: Would run: hal config --print"
else
    hal config --print 2>&1 | head -80 || warn "hal config --print exited non-zero; review output above."
fi

# ---------------------------------------------------------------------------
# Phase 13: Deploy Spinnaker
# ---------------------------------------------------------------------------
log "Phase 13: Deploying Spinnaker (hal deploy apply) ..."
log "This may take 5–15 minutes on first run ..."

if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY: Would run: hal deploy apply"
    log ""
    log "==================================================================="
    log "Dry-run complete. Review the hal commands above and re-run without"
    log "--dry-run to apply."
    log "==================================================================="
    exit 0
fi

hal deploy apply

# ---------------------------------------------------------------------------
# Phase 14: Post-install verification
# ---------------------------------------------------------------------------
log "Phase 14: Verifying Spinnaker services ..."

sleep 30   # Give services a moment to start

GATE_URL="http://localhost:8084"
log "Polling Spinnaker Gate at ${GATE_URL}/health ..."

HEALTHY=false
for attempt in $(seq 1 20); do
    STATUS=$(curl --silent --max-time 5 "${GATE_URL}/health" 2>/dev/null || true)
    if echo "${STATUS}" | grep -q '"status":"UP"' 2>/dev/null; then
        HEALTHY=true
        log "Gate is UP."
        break
    fi
    log "Gate health attempt ${attempt}/20: not ready yet — waiting 15s ..."
    sleep 15
done

if [[ "${HEALTHY}" != "true" ]]; then
    warn "Spinnaker Gate did not become healthy after ~5 minutes."
    warn "Check: journalctl -u spinnaker-gate --since '10 minutes ago'"
    warn "Or:    hal task list (for distributed deployments)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 15: Register SmartFreight pipelines
# ---------------------------------------------------------------------------
log "Phase 15: Registering SmartFreight pipelines ..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_SCRIPT="${SCRIPT_DIR}/register-pipelines.sh"

if [[ -f "${REGISTER_SCRIPT}" ]]; then
    bash "${REGISTER_SCRIPT}" \
        --gate-url "${GATE_URL}" \
        --pipelines-dir "${SCRIPT_DIR}/../pipelines"
else
    warn "register-pipelines.sh not found at ${REGISTER_SCRIPT} — skipping pipeline registration."
    warn "Run it manually once Spinnaker is running."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log ""
log "==================================================================="
log "Spinnaker ${SPINNAKER_VERSION} installation complete!"
log ""
log "  Spinnaker UI  : http://localhost:9000"
log "  Gate API      : http://localhost:8084"
log ""
log "Next steps:"
log "  1. Open http://localhost:9000 and verify the UI loads."
log "  2. Navigate to Applications → smartfreight → Pipelines."
log "  3. Confirm the shipment-service-pipeline is registered."
log "  4. Trigger a test build in Jenkins to exercise the full flow."
log "  5. For production: configure SSO (OAuth2/SAML), TLS, and"
log "     replace localhost URLs with real DNS entries."
log "==================================================================="
