#!/usr/bin/env bash
# =============================================================================
# SmartFreight Jenkins Agent — Entrypoint Script
# Launches the Jenkins Remoting agent JAR via JNLP connection.
# =============================================================================
set -euo pipefail

JAR="/usr/share/jenkins/agent.jar"
JENKINS_URL="${JENKINS_URL:-}"
JENKINS_SECRET="${JENKINS_SECRET:-}"
JENKINS_AGENT_NAME="${JENKINS_AGENT_NAME:-}"
JENKINS_TUNNEL="${JENKINS_TUNNEL:-}"
JENKINS_WEB_SOCKET="${JENKINS_WEB_SOCKET:-false}"

echo "[entrypoint] Starting SmartFreight Jenkins Agent"
echo "[entrypoint] Java: $(java -version 2>&1 | head -1)"
echo "[entrypoint] Maven: $(mvn --version 2>&1 | head -1)"
echo "[entrypoint] AWS CLI: $(aws --version 2>&1)"
echo "[entrypoint] Trivy: $(trivy --version 2>&1 | head -1)"

if [[ -z "${JENKINS_URL}" || -z "${JENKINS_SECRET}" || -z "${JENKINS_AGENT_NAME}" ]]; then
    echo "ERROR: JENKINS_URL, JENKINS_SECRET, and JENKINS_AGENT_NAME must all be set."
    echo "Usage: docker run -e JENKINS_URL=... -e JENKINS_SECRET=... -e JENKINS_AGENT_NAME=... smartfreight-jenkins-agent"
    exit 1
fi

JAVA_ARGS=(
    -jar "${JAR}"
    -jnlpUrl "${JENKINS_URL}/computer/${JENKINS_AGENT_NAME}/slave-agent.jnlp"
    -secret "${JENKINS_SECRET}"
    -workDir "${JENKINS_AGENT_WORKDIR:-/home/jenkins/agent}"
    -noReconnectAfter "1h"
)

if [[ -n "${JENKINS_TUNNEL}" ]]; then
    JAVA_ARGS+=(-tunnel "${JENKINS_TUNNEL}")
fi

if [[ "${JENKINS_WEB_SOCKET}" == "true" ]]; then
    JAVA_ARGS+=(-webSocket)
fi

exec java ${JAVA_OPTS:-} "${JAVA_ARGS[@]}"
