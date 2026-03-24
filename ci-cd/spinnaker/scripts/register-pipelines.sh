#!/usr/bin/env bash
# =============================================================================
# SmartFreight — Spinnaker Pipeline Registration Script
# =============================================================================
# Registers or updates all Spinnaker pipeline YAML files via the spin CLI
# or falls back to direct Gate API calls with curl.
#
# Requires PyYAML for YAML→JSON conversion:
#   pip3 install pyyaml
#
# Usage:
#   ./register-pipelines.sh [options]
#
# Options:
#   --gate-url URL        Spinnaker Gate URL (default: http://localhost:8084)
#   --token TOKEN         Bearer token for Gate API auth
#   --application APP     Only register pipelines for this app (default: all)
#   --pipelines-dir DIR   Directory containing *-pipeline.yaml files
#   --dry-run             Print actions without making API calls
#   --verbose             Show full curl output
# =============================================================================
set -euo pipefail

# ─── Defaults ─────────────────────────────────────────────────────────────────
GATE_URL="${SPINNAKER_GATE_URL:-http://localhost:8084}"
API_TOKEN="${SPINNAKER_TOKEN:-}"
FILTER_APP=""
PIPELINES_DIR="$(cd "$(dirname "$0")/../pipelines" && pwd)"
DRY_RUN=false
VERBOSE=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gate-url)       GATE_URL="$2";      shift 2 ;;
    --token)          API_TOKEN="$2";     shift 2 ;;
    --application)    FILTER_APP="$2";    shift 2 ;;
    --pipelines-dir)  PIPELINES_DIR="$2"; shift 2 ;;
    --dry-run)        DRY_RUN=true;       shift ;;
    --verbose)        VERBOSE=true;       shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()     { echo "[$(date '+%H:%M:%S')] $1"; }
ok()      { echo "[$(date '+%H:%M:%S')] ✅ $1"; }
warn()    { echo "[$(date '+%H:%M:%S')] ⚠️  $1" >&2; }
fail()    { echo "[$(date '+%H:%M:%S')] ❌ $1" >&2; }

# Build auth header string for curl
auth_header() {
  [[ -n "$API_TOKEN" ]] && echo "-H Authorization: Bearer ${API_TOKEN}" || echo ""
}

# ─── YAML → JSON converter ────────────────────────────────────────────────────
yaml_to_json() {
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 - "$file" << 'PY'
import sys, json
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
print(json.dumps(data, indent=2))
PY
  elif command -v yq &>/dev/null; then
    yq eval -o=json "$file"
  else
    fail "No YAML converter found. Install PyYAML: pip3 install pyyaml"
    exit 1
  fi
}

# ─── Gate helpers ─────────────────────────────────────────────────────────────
gate_get() {
  local path="$1"
  local token_arg=""
  [[ -n "$API_TOKEN" ]] && token_arg="-H 'Authorization: Bearer ${API_TOKEN}'"
  eval curl -sf $token_arg "\"${GATE_URL}${path}\""
}

gate_post() {
  local path="$1"
  local body="$2"
  local verbose_flag=""
  $VERBOSE && verbose_flag="-v"
  local token_arg=""
  [[ -n "$API_TOKEN" ]] && token_arg="-H 'Authorization: Bearer ${API_TOKEN}'"
  eval curl -sf $verbose_flag $token_arg \
    -X POST \
    -H "'Content-Type: application/json'" \
    -d "'${body}'" \
    "\"${GATE_URL}${path}\""
}

# ─── Gate health check ────────────────────────────────────────────────────────
check_gate() {
  log "Checking Spinnaker Gate at ${GATE_URL}..."
  local attempts=0
  until curl -sf "${GATE_URL}/health" 2>/dev/null | grep -q '"status":"UP"'; do
    attempts=$((attempts + 1))
    [[ $attempts -ge 5 ]] && { fail "Gate not reachable after 5 attempts"; exit 1; }
    warn "Gate not ready (attempt ${attempts}/5) — retrying in 5s..."
    sleep 5
  done
  ok "Gate is healthy"
}

# ─── Ensure Spinnaker application exists ─────────────────────────────────────
ensure_application() {
  local app="$1"
  if curl -sf "${GATE_URL}/applications/${app}" &>/dev/null; then
    log "  App '${app}' already exists"
    return 0
  fi
  log "  Creating Spinnaker application: ${app}"
  $DRY_RUN && { log "  [DRY RUN] Would create app '${app}'"; return 0; }
  local payload
  payload=$(python3 -c "
import json, sys
print(json.dumps({
  'job': [{'type': 'createApplication', 'application': {
    'name': '$app',
    'email': 'platform@smartfreight.com',
    'description': 'SmartFreight logistics platform',
    'cloudProviders': 'ecs',
    'platformHealthOnly': True,
  }}],
  'application': '$app',
  'description': 'Create application $app'
}))")
  curl -sf -X POST "${GATE_URL}/tasks" \
    -H "Content-Type: application/json" \
    ${API_TOKEN:+-H "Authorization: Bearer ${API_TOKEN}"} \
    -d "$payload" > /dev/null
  ok "  Created app '${app}'"
}

# ─── Register one pipeline ────────────────────────────────────────────────────
register_pipeline() {
  local yaml_file="$1"
  local filename
  filename=$(basename "$yaml_file")
  log "Processing: ${filename}"

  # Convert YAML → JSON
  local pipeline_json
  pipeline_json=$(yaml_to_json "$yaml_file") || { fail "YAML parse failed: ${filename}"; return 1; }

  # Extract app and name
  local app name
  app=$(python3  -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('application',''))" <<< "$pipeline_json")
  name=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('name',''))"        <<< "$pipeline_json")

  if [[ -z "$app" || -z "$name" ]]; then
    fail "Missing 'application' or 'name' in: ${filename}"
    return 1
  fi

  # App filter
  if [[ -n "$FILTER_APP" && "$app" != "$FILTER_APP" ]]; then
    log "  Skipping — app filter: ${FILTER_APP} ≠ ${app}"
    return 0
  fi

  log "  App: ${app}  |  Pipeline: ${name}"
  $DRY_RUN && { log "  [DRY RUN] Would register '${name}'"; return 0; }

  ensure_application "$app"

  # Try spin CLI first
  if command -v spin &>/dev/null; then
    local spin_args=(pipeline save --file "$yaml_file")
    [[ -n "$GATE_URL" ]]   && spin_args+=(--gate-endpoint "$GATE_URL")
    [[ -n "$API_TOKEN" ]]  && spin_args+=(--auth-token    "$API_TOKEN")
    if spin "${spin_args[@]}" 2>/dev/null; then
      ok "  Registered via spin: ${name}"
      return 0
    fi
    warn "  spin CLI failed — falling back to curl"
  fi

  # Fallback: POST to Gate /pipelines
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${GATE_URL}/pipelines" \
    -H "Content-Type: application/json" \
    ${API_TOKEN:+-H "Authorization: Bearer ${API_TOKEN}"} \
    -d "$pipeline_json")

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    ok "  Registered via Gate API: ${name} (HTTP ${http_code})"
    return 0
  else
    fail "  Failed: '${name}' — Gate returned HTTP ${http_code}"
    return 1
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "========================================================"
  log "SmartFreight — Spinnaker Pipeline Registration"
  log "  Gate URL:    ${GATE_URL}"
  log "  Pipelines:   ${PIPELINES_DIR}"
  log "  App filter:  ${FILTER_APP:-all}"
  log "  Dry run:     ${DRY_RUN}"
  log "========================================================"

  # Collect pipeline YAML files
  local yaml_files=()
  while IFS= read -r -d '' f; do
    yaml_files+=("$f")
  done < <(find "$PIPELINES_DIR" -maxdepth 1 -name "*-pipeline.yaml" -print0 | sort -z)

  if [[ ${#yaml_files[@]} -eq 0 ]]; then
    warn "No *-pipeline.yaml files found in: ${PIPELINES_DIR}"
    exit 0
  fi

  log "Found ${#yaml_files[@]} pipeline(s)"
  echo ""

  $DRY_RUN || check_gate

  local total=0 succeeded=0 failed=0
  local failed_names=()

  for f in "${yaml_files[@]}"; do
    total=$((total + 1))
    if register_pipeline "$f"; then
      succeeded=$((succeeded + 1))
    else
      failed=$((failed + 1))
      failed_names+=("$(basename "$f")")
    fi
    echo ""
  done

  log "========================================================"
  log "Summary: total=${total}  succeeded=${succeeded}  failed=${failed}"
  if [[ ${#failed_names[@]} -gt 0 ]]; then
    fail "Failed pipelines:"
    for n in "${failed_names[@]}"; do fail "  - ${n}"; done
  fi
  log "========================================================"

  [[ $failed -eq 0 ]]
}

main
