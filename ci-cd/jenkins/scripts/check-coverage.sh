#!/usr/bin/env bash
# =============================================================================
# SmartFreight — check-coverage.sh
#
# Reads a JaCoCo XML report and asserts that line coverage meets the threshold.
#
# Usage:
#   ./check-coverage.sh <JACOCO_XML_PATH> [THRESHOLD]
#
# Arguments:
#   JACOCO_XML_PATH   Path to JaCoCo XML report (e.g. target/site/jacoco/jacoco.xml)
#   THRESHOLD         Minimum line coverage percentage, integer 0-100 (default: 80)
#
# Exit codes:
#   0  — Coverage meets or exceeds threshold
#   1  — Coverage is below threshold, or XML file is missing/unreadable
#
# Dependencies (in preference order):
#   1. xmllint   (libxml2-utils, fastest — used if available)
#   2. python3   (fallback — uses xml.etree.ElementTree from stdlib)
#
# The JaCoCo XML format for the BUNDLE report element:
#   <report>
#     <counter type="LINE" missed="NNN" covered="MMM"/>
#   </report>
# Coverage = covered / (covered + missed) * 100
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[check-coverage] $*"; }
err()  { echo "[check-coverage] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
JACOCO_XML="${1:-}"
THRESHOLD="${2:-80}"

if [[ -z "${JACOCO_XML}" ]]; then
    # Auto-discover the first jacoco.xml found under the current directory
    JACOCO_XML=$(find . -name "jacoco.xml" -path "*/site/jacoco/*" | head -1 || true)
    if [[ -z "${JACOCO_XML}" ]]; then
        die "No JaCoCo XML path provided and none found under the current directory."
    fi
    log "Auto-discovered JaCoCo report: ${JACOCO_XML}"
fi

# Validate threshold is an integer between 0 and 100
if ! [[ "${THRESHOLD}" =~ ^[0-9]+$ ]] || (( THRESHOLD < 0 || THRESHOLD > 100 )); then
    die "THRESHOLD must be an integer between 0 and 100. Got: '${THRESHOLD}'"
fi

# Validate the XML file exists and is readable
if [[ ! -f "${JACOCO_XML}" ]]; then
    die "JaCoCo XML report not found at: ${JACOCO_XML}"
fi

if [[ ! -r "${JACOCO_XML}" ]]; then
    die "JaCoCo XML report is not readable: ${JACOCO_XML}"
fi

log "Report    : ${JACOCO_XML}"
log "Threshold : ${THRESHOLD}%"

# ---------------------------------------------------------------------------
# Parse LINE counter values from the BUNDLE-level <counter type="LINE"> element.
#
# JaCoCo XML structure (abbreviated):
#   <report name="...">
#     ...
#     <counter type="LINE" missed="123" covered="456"/>
#   </report>
#
# The BUNDLE-level counters are direct children of <report>, not nested inside
# <package> or <class> elements. We grab the last occurrence of
# <counter type="LINE"> which is always the BUNDLE aggregate.
# ---------------------------------------------------------------------------

parse_with_xmllint() {
    local xml_file="${1}"

    # Extract covered and missed line counts from the report-level LINE counter.
    # XPath: /report/counter[@type='LINE']/@covered and /@missed
    local covered missed
    covered=$(xmllint --xpath \
        "string(/report/counter[@type='LINE']/@covered)" \
        "${xml_file}" 2>/dev/null) || true
    missed=$(xmllint --xpath \
        "string(/report/counter[@type='LINE']/@missed)" \
        "${xml_file}" 2>/dev/null) || true

    echo "${covered} ${missed}"
}

parse_with_python() {
    local xml_file="${1}"

    python3 - "${xml_file}" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET

xml_path = sys.argv[1]
try:
    # JaCoCo XML uses a DOCTYPE that references a DTD which may be unavailable
    # in CI environments. Parse without validating the DTD.
    tree = ET.parse(xml_path)
    root = tree.getroot()
except ET.ParseError as exc:
    print(f"ERROR: Failed to parse XML: {exc}", file=sys.stderr)
    sys.exit(1)

# The report-level LINE counter is a direct child of <report> (root element)
covered = 0
missed  = 0
for counter in root.findall("counter"):
    if counter.get("type") == "LINE":
        covered = int(counter.get("covered", 0))
        missed  = int(counter.get("missed",  0))
        break

if covered == 0 and missed == 0:
    print("ERROR: No LINE counter found at report level in JaCoCo XML", file=sys.stderr)
    sys.exit(1)

print(f"{covered} {missed}")
PYTHON
}

# ---------------------------------------------------------------------------
# Choose parser
# ---------------------------------------------------------------------------
COVERED=""
MISSED=""

if command -v xmllint &>/dev/null; then
    log "Using xmllint to parse JaCoCo XML ..."
    READ_RESULT=$(parse_with_xmllint "${JACOCO_XML}") || \
        die "xmllint failed to parse ${JACOCO_XML}"
elif command -v python3 &>/dev/null; then
    log "xmllint not available, using python3 to parse JaCoCo XML ..."
    READ_RESULT=$(parse_with_python "${JACOCO_XML}") || \
        die "python3 failed to parse ${JACOCO_XML}"
else
    die "Neither xmllint nor python3 is available. Cannot parse JaCoCo XML."
fi

COVERED=$(echo "${READ_RESULT}" | awk '{print $1}')
MISSED=$(echo "${READ_RESULT}"  | awk '{print $2}')

# Validate we got numeric values
if ! [[ "${COVERED}" =~ ^[0-9]+$ ]]; then
    die "Unexpected 'covered' value from XML parser: '${COVERED}'. Report may be empty or malformed."
fi
if ! [[ "${MISSED}" =~ ^[0-9]+$ ]]; then
    die "Unexpected 'missed' value from XML parser: '${MISSED}'. Report may be empty or malformed."
fi

TOTAL=$(( COVERED + MISSED ))

if (( TOTAL == 0 )); then
    die "JaCoCo LINE counter shows 0 total lines. Tests may not have run, or the report is empty."
fi

# ---------------------------------------------------------------------------
# Calculate coverage percentage (integer arithmetic, rounds down)
# ---------------------------------------------------------------------------
# Use awk for reliable floating-point percentage calculation
COVERAGE_FLOAT=$(awk "BEGIN { printf \"%.2f\", (${COVERED} / ${TOTAL}) * 100 }")
COVERAGE_INT=$(awk "BEGIN { printf \"%d\", (${COVERED} / ${TOTAL}) * 100 }")

log "Lines covered : ${COVERED}"
log "Lines missed  : ${MISSED}"
log "Total lines   : ${TOTAL}"
log "Coverage      : ${COVERAGE_FLOAT}%"
log "Threshold     : ${THRESHOLD}%"

# ---------------------------------------------------------------------------
# Gate check
# ---------------------------------------------------------------------------
if (( COVERAGE_INT >= THRESHOLD )); then
    log "PASS: Line coverage ${COVERAGE_FLOAT}% >= ${THRESHOLD}% threshold."
    exit 0
else
    log "==================================================================="
    err "FAIL: Line coverage ${COVERAGE_FLOAT}% is BELOW the ${THRESHOLD}% threshold."
    err "      ${MISSED} lines are not covered by tests."
    err "      Add unit tests to bring coverage above ${THRESHOLD}%."
    log "==================================================================="
    exit 1
fi
