#!/bin/bash
#
# debug-smoke-test.sh
# Variant of your smoke test with a run_cmd wrapper to detect segfaults (exit 139)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../../lib/bash/common.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/../../lib/bash/common.sh"
fi

# Logging setup
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/smoke-test-debug.log"
: > "${LOG_FILE}"

log_to_file() {
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s %s\n' "${ts}" "$*" >> "${LOG_FILE}"
}

call_if_func() {
    local func="$1"; shift
    if declare -F "${func}" >/dev/null 2>&1; then
        "${func}" "$@"
    else
        echo "$@"
    fi
}

log_test()    { call_if_func log_test    "$@"; log_to_file "[TEST] $*"; }
log_header()  { call_if_func log_header  "$@"; log_to_file "[HEADER] $*"; }
log_section() { call_if_func log_section "$@"; log_to_file "[SECTION] $*"; }
log_info()    { call_if_func log_info    "$@"; log_to_file "[INFO] $*"; }
log_pass()    { call_if_func log_pass    "$@"; log_to_file "[PASS] $*"; }
log_fail()    { call_if_func log_fail    "$@"; log_to_file "[FAIL] $*"; }
log_warn()    { call_if_func log_warn    "$@"; log_to_file "[WARN] $*"; }
log_success() { call_if_func log_success "$@"; log_to_file "[SUCCESS] $*"; }
log_error()   { call_if_func log_error   "$@"; log_to_file "[ERROR] $*"; }

# wrapper that runs a command, logs it, appends stderr to LOG_FILE, captures exit code
# usage: run_cmd <cmd> [args...]
run_cmd() {
    # print command for humans and log it
    log_to_file "[CMD] $*"
    echo "[CMD] $*"

    # Run command: stdout goes to stdout, stderr appended to log file
    "$@" 2>> "${LOG_FILE}"
    local rc=$?

    # Write explicit record to log file with rc
    log_to_file "[RC] ${rc} - $*"

    # Detect segfault (exit code 139)
    if [[ ${rc} -eq 139 ]]; then
        log_error "SEGMENTATION FAULT detected (exit code 139) while running: $*"
        log_to_file "STACK: (no stack from shell) - check core dump or binary logs"
        echo "SEGMENTATION FAULT detected while running: $*"
        echo "See ${LOG_FILE} for details."
        # Try to enable core dump and suggest next steps
        echo "If you want to capture a core dump, rerun with ulimit -c unlimited and reproduce the error."
        # Stop execution so user can investigate
        exit 139
    fi

    return ${rc}
}

# kubectl wrapper that uses run_cmd but still appends kubectl stderr to log (run_cmd already does)
kubectl_run() {
    run_cmd kubectl "$@"
}

# configure
NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
NAMESPACE_EXISTS=false

log_header "SAS Viya Smoke Tests - Debug Run"
log_info "Namespace: ${NAMESPACE}"
log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ") (UTC)"
log_to_file "Starting debug smoke test for namespace=${NAMESPACE}"
echo ""

# ------------------------------
# Test 1
# ------------------------------
test_cluster_connectivity() {
    log_test "[1/8] Checking cluster connectivity"
    if run_cmd kubectl cluster-info &>/dev/null; then
        log_pass "Cluster is accessible"
        ((PASSED_TESTS++))
    else
        log_fail "Cannot connect to cluster"
        log_to_file "kubectl cluster-info returned non-zero"
        ((FAILED_TESTS++))
    fi
}

# ------------------------------
# Test 2
# ------------------------------
test_list_namespaces() {
    log_test "[2/8] Listing available namespaces"
    local namespaces
    # capture stdout of kubectl (run_cmd prints the command and logs errors)
    namespaces=$(kubectl_run get namespaces --no-headers 2>/dev/null | awk '{print $1}') || true

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
        log_to_file "kubectl get namespaces failed or returned nothing"
        ((FAILED_TESTS++))
    fi
}

# ------------------------------
# Test 3
# ------------------------------
test_namespace() {
    log_test "[3/8] Checking namespace '${NAMESPACE}' exists"
    if kubectl_run get namespace "${NAMESPACE}" &>/dev/null; then
        log_pass "Namespace ${NAMESPACE} exists"
        ((PASSED_TESTS++))
        NAMESPACE_EXISTS=true
    else
        log_fail "Namespace ${NAMESPACE} not found"
        log_to_file "Namespace check failed for ${NAMESPACE}"
        ((FAILED_TESTS++))
        NAMESPACE_EXISTS=false
        log_warn "Tests 4-8 will be skipped if namespace missing"
    fi
}

# ------------------------------
# Test 4
# ------------------------------
test_cas_controller() {
    log_test "[4/8] Checking CAS Controller"
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local cas_pods
    cas_pods=$(kubectl_run get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=sas-cas-server" --no-headers 2>/dev/null | wc -l) || cas_pods=0
    cas_pods=${cas_pods:-0}
    if [[ ${cas_pods} -gt 0 ]]; then
        log_pass "CAS Controller found (${cas_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "CAS Controller not found"
        log_to_file "no CAS pods in ${NAMESPACE}"
        ((FAILED_TESTS++))
    fi
}

# ------------------------------
# Test 5
# ------------------------------
test_core_services() {
    log_test "[5/8] Checking Services in Namespace '${NAMESPACE}'"
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local services=("sas-logon-app" "sas-identities" "sas-authorization")
    local found=0
    local total=3

    log_info "All services in namespace ${NAMESPACE}:"
    local all_services
    all_services=$(kubectl_run get svc -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{print $1}') || true

    if [ -z "${all_services}" ]; then
        log_fail "No services found in namespace ${NAMESPACE}"
        log_to_file "kubectl get svc failed for ${NAMESPACE}"
        ((FAILED_TESTS++))
        return
    fi

    while read -r svc; do
        [ -z "${svc}" ] && continue
        log_info "  - ${svc}"
    done <<< "${all_services}"

    log_info "Checking required core services:"
    for service in "${services[@]}"; do
        if kubectl_run get service "${service}" -n "${NAMESPACE}" &>/dev/null; then
            log_info "  ✓ ${service}"
            ((found++))
        else
            log_warn "  ✗ ${service}"
            log_to_file "Core service missing: ${service}"
        fi
    done

    if [[ ${found} -eq ${total} ]]; then
        log_pass "All core services present (${found}/${total})"
        ((PASSED_TESTS++))
    else
        log_fail "Only ${found}/${total} core services found"
        ((FAILED_TESTS++))
    fi
}

# ------------------------------
# Test 6
# ------------------------------
test_database() {
    log_test "[6/8] Checking PostgreSQL Database"
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local pg_pods
    pg_pods=$(kubectl_run get pods -n "${NAMESPACE}" -l "app=sas-postgres" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l) || pg_pods=0
    pg_pods=${pg_pods:-0}
    if [[ ${pg_pods} -gt 0 ]]; then
        log_pass "PostgreSQL running (${pg_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "PostgreSQL not found or not running"
        log_to_file "Postgres pods missing/running check failed"
        ((FAILED_TESTS++))
    fi
}

# ------------------------------
# Test 7
# ------------------------------
test_ingress() {
    log_test "[7/8] Checking Ingress Configuration"
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local ingress_count
    ingress_count=$(kubectl_run get ingress -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l) || ingress_count=0
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

# ------------------------------
# Test 8
# ------------------------------
test_events() {
    log_test "[8/8] Checking for Warning Events"
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi

    local warning_lines
    warning_lines=$(kubectl_run get events -n "${NAMESPACE}" --field-selector type=Warning --no-headers 2>/dev/null) || true
    local warnings_count
    warnings_count=$(echo "${warning_lines}" | grep -cve '^\s*$' || true)
    warnings_count=${warnings_count:-0}

    if [[ ${warnings_count} -eq 0 ]]; then
        log_pass "No warning events found"
        ((PASSED_TESTS++))
    else
        log_warn "${warnings_count} warning event(s) found"
        log_to_file "------ WARNING EVENTS FOR NAMESPACE ${NAMESPACE} ------"
        kubectl_run get events -n "${NAMESPACE}" --field-selector type=Warning --sort-by=.lastTimestamp -o custom-columns='LAST:.lastTimestamp,NS:.metadata.namespace,OBJ:.involvedObject.name,REASON:.reason,MESSAGE:.message' --no-headers >> "${LOG_FILE}" 2>>"${LOG_FILE}" || true
        echo "" >> "${LOG_FILE}"
        echo "${warning_lines}" >> "${LOG_FILE}" 2>>"${LOG_FILE}"
        if [[ ${warnings_count} -gt 5 ]]; then
            log_fail "${warnings_count} warning events found (too many)"
            ((FAILED_TESTS++))
        else
            log_warn "${warnings_count} warning events found (acceptable)"
            ((PASSED_TESTS++))
        fi
    fi
}

# ==========================
# RUN TESTS
# ==========================
log_section "Starting Test Suite (8 tests)"

test_cluster_connectivity; echo ""
test_list_namespaces; echo ""
test_namespace; echo ""
test_cas_controller; echo ""
test_core_services; echo ""
test_database; echo ""
test_ingress; echo ""
test_events; echo ""

# ==========================
# SUMMARY
# ==========================
log_header "Test Execution Complete"
log_info "Total Tests Run: 8"
log_success "Passed: ${PASSED_TESTS}"
log_error "Failed: ${FAILED_TESTS}"
log_warn "Skipped: ${SKIPPED_TESTS}"
log_to_file "SUMMARY: passed=${PASSED_TESTS} failed=${FAILED_TESTS} skipped=${SKIPPED_TESTS}"

if [[ ${FAILED_TESTS} -eq 0 && ${SKIPPED_TESTS} -eq 0 ]]; then
    log_success "✓ All tests passed successfully!"
    log_to_file "Exit: 0"
    exit 0
elif [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "✗ ${FAILED_TESTS} test(s) failed. See ${LOG_FILE}"
    echo "DEBUG LOG: ${LOG_FILE}" >&2
    log_to_file "Exit: 1"
    exit 1
else
    log_warn "⚠ Some tests were skipped. See ${LOG_FILE}"
    echo "DEBUG LOG: ${LOG_FILE}" >&2
    log_to_file "Exit: 0 (skipped)"
    exit 0
fi
