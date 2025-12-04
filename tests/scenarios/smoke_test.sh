#!/bin/bash
#
# smoke-test.sh
# Enhanced: writes failures/warnings/kubectl stderr and event details to logs/smoke-test-debug.log
#
# Usage:
#   ./smoke-test.sh <namespace>
#   e.g. ./smoke-test.sh sas-viya
#

# Do NOT set -e so script continues on errors
# set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# source existing logging helpers if present
# keep this at top so wrapped log functions can call originals if available
if [ -f "${SCRIPT_DIR}/../../lib/bash/common.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/../../lib/bash/common.sh"
fi

# Log file path inside logs/ directory (as requested)
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/smoke-test-debug.log"
: > "${LOG_FILE}"   # truncate/start fresh

# Helper: append to log file with timestamp
log_to_file() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    # join args to message
    printf '%s %s\n' "${ts}" "$*" >> "${LOG_FILE}"
}

# Wrap/override logging functions so they both print to STDOUT (using existing functions if available)
# and always write to the log file.
# If the common.sh provided functions (log_info, log_warn, etc.) exist, call them as well.

call_if_func() {
    local func="$1"; shift
    if declare -F "${func}" >/dev/null 2>&1; then
        # call the original function with the remaining args
        "${func}" "$@"
    else
        # fallback to plain echo for display
        echo "$@"
    fi
}

log_test() {
    local msg="$*"
    call_if_func log_test "${msg}"
    log_to_file "[TEST] ${msg}"
}

log_header() {
    local msg="$*"
    call_if_func log_header "${msg}"
    log_to_file "[HEADER] ${msg}"
}

log_section() {
    local msg="$*"
    call_if_func log_section "${msg}"
    log_to_file "[SECTION] ${msg}"
}

log_info() {
    local msg="$*"
    call_if_func log_info "${msg}"
    log_to_file "[INFO] ${msg}"
}

log_pass() {
    local msg="$*"
    call_if_func log_pass "${msg}"
    log_to_file "[PASS] ${msg}"
}

log_fail() {
    local msg="$*"
    call_if_func log_fail "${msg}"
    log_to_file "[FAIL] ${msg}"
}

log_warn() {
    local msg="$*"
    call_if_func log_warn "${msg}"
    log_to_file "[WARN] ${msg}"
}

log_success() {
    local msg="$*"
    call_if_func log_success "${msg}"
    log_to_file "[SUCCESS] ${msg}"
}

log_error() {
    local msg="$*"
    call_if_func log_error "${msg}"
    log_to_file "[ERROR] ${msg}"
}

# kubectl wrapper: writes kubectl stderr to the log file while preserving stdout for consumption
kubectl_with_log() {
    # We want exit code semantics similar to kubectl. We'll run kubectl and capture its exit code.
    # stdout goes to caller, stderr appended to LOG_FILE.
    # Use "kubectl" binary directly; pass all args.
    kubectl "$@" 2>> "${LOG_FILE}"
    return $?
}

# variables and counters
NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
NAMESPACE_EXISTS=false

log_header "SAS Viya Smoke Tests - Full Run"
log_info "Namespace: ${NAMESPACE}"
log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ") (UTC)"
log_info "Will run all 8 tests in sequence"
log_to_file "Starting smoke test for namespace=${NAMESPACE}"
echo ""

# -----------------
# Test 1: Cluster connectivity
# -----------------
test_cluster_connectivity() {
    log_test "[1/8] Checking cluster connectivity"

    if kubectl_with_log cluster-info &>/dev/null; then
        log_pass "Cluster is accessible"
        ((PASSED_TESTS++))
    else
        log_fail "Cannot connect to cluster"
        log_to_file "kubectl cluster-info failed (see stderr above)"
        ((FAILED_TESTS++))
    fi
}

# -----------------
# Test 2: List available namespaces
# -----------------
test_list_namespaces() {
    log_test "[2/8] Listing available namespaces"

    local namespaces
    # capture stdout of kubectl_with_log
    namespaces=$(kubectl_with_log get namespaces --no-headers 2>/dev/null | awk '{print $1}') || true

    if [ -n "${namespaces}" ]; then
        log_info "Found namespaces:"

        while read -r ns; do
            [ -z "$ns" ] && continue
            if [[ "${ns}" == *"sas"* ]] || [[ "${ns}" == *"viya"* ]]; then
                log_info "  → ${ns} (possible SAS Viya namespace)"
            else
                log_info "  - ${ns}"
            fi
        done <<< "${namespaces}"

        ((PASSED_TESTS++))
    else
        log_fail "Cannot list namespaces"
        log_to_file "kubectl get namespaces returned no output or failed"
        ((FAILED_TESTS++))
    fi
}

# -----------------
# Test 3: Namespace exists
# -----------------
test_namespace() {
    log_test "[3/8] Checking if namespace '${NAMESPACE}' exists"

    if kubectl_with_log get namespace "${NAMESPACE}" &>/dev/null; then
        log_pass "Namespace ${NAMESPACE} exists"
        ((PASSED_TESTS++))
        NAMESPACE_EXISTS=true
    else
        log_fail "Namespace ${NAMESPACE} not found"
        log_to_file "Namespace check failed for ${NAMESPACE}"
        ((FAILED_TESTS++))
        NAMESPACE_EXISTS=false
        log_warn "Tests 4-8 will be skipped since namespace doesn't exist"
    fi
}

# -----------------
# Test 4: CAS Controller
# -----------------
test_cas_controller() {
    log_test "[4/8] Checking CAS Controller"

    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local cas_pods
    cas_pods=$(kubectl_with_log get pods -n "${NAMESPACE}" \
        -l "app.kubernetes.io/name=sas-cas-server" \
        --no-headers 2>/dev/null | wc -l) || cas_pods=0

    cas_pods=${cas_pods:-0}
    if [[ ${cas_pods} -gt 0 ]]; then
        log_pass "CAS Controller found (${cas_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "CAS Controller not found"
        log_to_file "No CAS pods in ${NAMESPACE}"
        ((FAILED_TESTS++))
    fi
}

# -----------------
# Test 5: Core Services (and list all services)
# -----------------
test_core_services() {
    log_test "[5/8] Checking Services in Namespace '${NAMESPACE}'"

    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        echo ""
        return
    fi

    # Core services required
    local services=("sas-logon-app" "sas-identities" "sas-authorization")
    local found=0
    local total=3

    log_info "All services in namespace ${NAMESPACE}:"

    local all_services
    all_services=$(kubectl_with_log get svc -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{print $1}') || true

    if [ -z "${all_services}" ]; then
        log_fail "No services found in namespace ${NAMESPACE}"
        log_to_file "kubectl get svc failed or returned no services for ${NAMESPACE}"
        ((FAILED_TESTS++))
        echo ""
        return
    fi

    while read -r svc; do
        [ -z "${svc}" ] && continue
        log_info "  - ${svc}"
    done <<< "${all_services}"

    echo ""
    log_info "Checking required core services:"
    for service in "${services[@]}"; do
        if kubectl_with_log get service "${service}" -n "${NAMESPACE}" &>/dev/null; then
            log_info "  ✓ ${service}"
            ((found++))
        else
            log_warn "  ✗ ${service}"
            log_to_file "Core service missing: ${service} in ${NAMESPACE}"
        fi
    done

    if [[ ${found} -eq ${total} ]]; then
        log_pass "All core services present (${found}/${total})"
        ((PASSED_TESTS++))
    else
        log_fail "Only ${found}/${total} core services found"
        ((FAILED_TESTS++))
    fi

    echo ""
}

# -----------------
# Test 6: Database
# -----------------
test_database() {
    log_test "[6/8] Checking PostgreSQL Database"

    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local pg_pods
    pg_pods=$(kubectl_with_log get pods -n "${NAMESPACE}" \
        -l "app=sas-postgres" \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l) || pg_pods=0

    pg_pods=${pg_pods:-0}
    if [[ ${pg_pods} -gt 0 ]]; then
        log_pass "PostgreSQL running (${pg_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "PostgreSQL not found or not running"
        log_to_file "PostgreSQL pods not running in ${NAMESPACE}"
        ((FAILED_TESTS++))
    fi
}

# -----------------
# Test 7: Ingress
# -----------------
test_ingress() {
    log_test "[7/8] Checking Ingress Configuration"

    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local ingress_count
    ingress_count=$(kubectl_with_log get ingress -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l) || ingress_count=0
    ingress_count=${ingress_count:-0}

    if [[ ${ingress_count} -gt 0 ]]; then
        log_pass "Ingress configured (${ingress_count} rules)"
        ((PASSED_TESTS++))
    else
        log_warn "No ingress configured (may be optional)"
        log_to_file "No ingress in ${NAMESPACE}"
        ((PASSED_TESTS++))
    fi
}

# -----------------
# Test 8: Recent Events (Warnings) - detailed + write to log file
# -----------------
test_events() {
    log_test "[8/8] Checking for Warning Events"

    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    # Get warning event lines (human readable)
    local warning_lines
    warning_lines=$(kubectl_with_log get events -n "${NAMESPACE}" --field-selector type=Warning --no-headers 2>/dev/null) || true

    # Count warnings (empty safely handled)
    local warnings_count
    warnings_count=$(echo "${warning_lines}" | grep -cve '^\s*$' || true)
    warnings_count=${warnings_count:-0}

    if [[ ${warnings_count} -eq 0 ]]; then
        log_pass "No warning events found"
        ((PASSED_TESTS++))
    else
        log_warn "${warnings_count} warning event(s) found"
        log_to_file "------ WARNING EVENTS FOR NAMESPACE ${NAMESPACE} ------"
        # Save a cleaned detailed table (timestamp, involvedObject, reason, message)
        kubectl_with_log get events -n "${NAMESPACE}" --field-selector type=Warning \
            --sort-by=.lastTimestamp \
            -o custom-columns='LASTTIMESTAMP:.lastTimestamp,NAMESPACE:.metadata.namespace,OBJ:.involvedObject.name,REASON:.reason,MESSAGE:.message' \
            --no-headers >> "${LOG_FILE}" 2>>"${LOG_FILE}" || true
        echo "" >> "${LOG_FILE}"

        # Also append the original human-readable event lines for direct debugging
        echo "${warning_lines}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"

        if [[ ${warnings_count} -gt 5 ]]; then
            log_fail "${warnings_count} warning events found (too many)"
            ((FAILED_TESTS++))
        else
            log_warn "${warnings_count} warning events found (acceptable threshold)"
            ((PASSED_TESTS++))
        fi
    fi
}

# =========================================
# MAIN - run all tests in order
# =========================================

log_section "Starting Test Suite (8 tests)"

test_cluster_connectivity
echo ""

test_list_namespaces
echo ""

test_namespace
echo ""

test_cas_controller
echo ""

test_core_services
echo ""

test_database
echo ""

test_ingress
echo ""

test_events
echo ""

# =========================================
# FINAL SUMMARY
# =========================================

log_header "Test Execution Complete"
log_info "Total Tests Run: 8"
log_success "Passed: ${PASSED_TESTS}"
log_error "Failed: ${FAILED_TESTS}"
log_warn "Skipped: ${SKIPPED_TESTS}"

log_to_file "SUMMARY: passed=${PASSED_TESTS} failed=${FAILED_TESTS} skipped=${SKIPPED_TESTS}"

echo ""
log_section "Recommendations"

if [[ ${NAMESPACE_EXISTS} = false ]]; then
    log_warn "The namespace '${NAMESPACE}' does not exist."
    log_info "Try running with one of the namespaces listed in Test 2"
    log_info "Example: $0 <actual-namespace>"
fi

# final exit codes
if [[ ${FAILED_TESTS} -eq 0 && ${SKIPPED_TESTS} -eq 0 ]]; then
    log_success "✓ All tests passed successfully!"
    log_to_file "Exit: 0 - all tests passed"
    exit 0
elif [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "✗ ${FAILED_TESTS} test(s) failed. Review the output and the log file: ${LOG_FILE}"
    log_to_file "Exit: 1 - ${FAILED_TESTS} failed"
    # print location of log file on stderr for pipelines
    echo "DEBUG LOG: ${LOG_FILE}" >&2
    exit 1
else
    log_warn "⚠ Some tests were skipped. Review the output above."
    log_to_file "Exit: 0 - some tests skipped"
    echo "DEBUG LOG: ${LOG_FILE}" >&2
    exit 0
fi
