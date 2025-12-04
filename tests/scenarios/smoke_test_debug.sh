#!/bin/bash
#
# Full SAS Viya Smoke Test - checks infra stability & completeness
# All failures and warnings are logged to logs/smoke-test.log
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/smoke-test.log"
: > "${LOG_FILE}"

# Load common functions if available
if [ -f "${SCRIPT_DIR}/../../lib/bash/common.sh" ]; then
    source "${SCRIPT_DIR}/../../lib/bash/common.sh"
fi

NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
NAMESPACE_EXISTS=false

log_to_file() { 
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >> "${LOG_FILE}"
}

# Wrappers to log messages both to stdout and log file
log()        { echo "$*"; log_to_file "$*"; }
log_header() { echo ""; echo "===== $* ====="; log_to_file "===== $* ====="; echo ""; }
log_section(){ echo ""; echo "---- $* ----"; log_to_file "---- $* ----"; echo ""; }
log_info()   { echo "[INFO] $*"; log_to_file "[INFO] $*"; }
log_warn()   { echo "[WARN] $*"; log_to_file "[WARN] $*"; }
log_pass()   { echo "[PASS] $*"; log_to_file "[PASS] $*"; }
log_fail()   { echo "[FAIL] $*"; log_to_file "[FAIL] $*"; }

# Run command wrapper to capture errors/warnings
run_cmd() {
    echo "[CMD] $*" 
    log_to_file "[CMD] $*"
    "$@" 2>> "${LOG_FILE}"
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_to_file "[RC=$rc] $*"
    fi
    return $rc
}

# ----------------------------
# TESTS
# ----------------------------

# 1. Cluster connectivity
test_cluster_connectivity() {
    log_header "[1/8] Cluster Connectivity"
    if run_cmd kubectl cluster-info &>/dev/null; then
        log_pass "Cluster is accessible"
        ((PASSED_TESTS++))
    else
        log_fail "Cannot connect to cluster"
        ((FAILED_TESTS++))
    fi
}

# 2. List namespaces
test_list_namespaces() {
    log_header "[2/8] Listing Namespaces"
    local namespaces
    namespaces=$(run_cmd kubectl get namespaces --no-headers | awk '{print $1}') || namespaces=""
    if [ -n "$namespaces" ]; then
        log_info "Namespaces found:"
        while read -r ns; do
            [ -z "$ns" ] && continue
            if [[ "$ns" == *sas* ]] || [[ "$ns" == *viya* ]]; then
                log_info "  → $ns (possible SAS Viya namespace)"
            else
                log_info "  - $ns"
            fi
        done <<< "$namespaces"
        ((PASSED_TESTS++))
    else
        log_fail "No namespaces could be listed"
        ((FAILED_TESTS++))
    fi
}

# 3. Namespace exists
test_namespace() {
    log_header "[3/8] Checking Namespace '${NAMESPACE}'"
    if run_cmd kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_pass "Namespace $NAMESPACE exists"
        ((PASSED_TESTS++))
        NAMESPACE_EXISTS=true
    else
        log_fail "Namespace $NAMESPACE does not exist"
        ((FAILED_TESTS++))
        NAMESPACE_EXISTS=false
        log_warn "Tests 4-8 will be skipped since namespace is missing"
    fi
}

# 4. CAS Controller
test_cas_controller() {
    log_header "[4/8] CAS Controller"
    if [ "$NAMESPACE_EXISTS" = false ]; then
        log_warn "SKIPPED - namespace missing"
        ((SKIPPED_TESTS++))
        return
    fi
    local count
    count=$(run_cmd kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=sas-cas-server" --no-headers | wc -l)
    if [ "$count" -gt 0 ]; then
        log_pass "CAS Controller pods found: $count"
        ((PASSED_TESTS++))
    else
        log_fail "No CAS Controller pods found"
        ((FAILED_TESTS++))
    fi
}

# 5. Services
test_services() {
    log_header "[5/8] Services in Namespace '$NAMESPACE'"
    if [ "$NAMESPACE_EXISTS" = false ]; then
        log_warn "SKIPPED - namespace missing"
        ((SKIPPED_TESTS++))
        return
    fi

    # List all services
    log_info "All services:"
    local all_services
    all_services=$(run_cmd kubectl get svc -n "$NAMESPACE" --no-headers | awk '{print $1}')
    if [ -n "$all_services" ]; then
        while read -r svc; do
            [ -z "$svc" ] && continue
            log_info "  - $svc"
        done <<< "$all_services"
    else
        log_warn "No services found in namespace"
    fi

    # Check core services
    local core=("sas-logon-app" "sas-identities" "sas-authorization")
    local found=0
    for s in "${core[@]}"; do
        if run_cmd kubectl get svc "$s" -n "$NAMESPACE" &>/dev/null; then
            log_info "  ✓ $s"
            ((found++))
        else
            log_warn "  ✗ $s"
            log_to_file "Core service missing: $s"
        fi
    done

    if [ "$found" -eq "${#core[@]}" ]; then
        log_pass "All core services present"
        ((PASSED_TESTS++))
    else
        log_fail "Some core services missing ($found/${#core[@]})"
        ((FAILED_TESTS++))
    fi
}

# 6. Database
test_database() {
    log_header "[6/8] PostgreSQL Database"
    if [ "$NAMESPACE_EXISTS" = false ]; then
        log_warn "SKIPPED - namespace missing"
        ((SKIPPED_TESTS++))
        return
    fi
    local count
    count=$(run_cmd kubectl get pods -n "$NAMESPACE" -l "app=sas-postgres" --field-selector=status.phase=Running --no-headers | wc -l)
    if [ "$count" -gt 0 ]; then
        log_pass "PostgreSQL running pods: $count"
        ((PASSED_TESTS++))
    else
        log_fail "PostgreSQL not running or missing"
        ((FAILED_TESTS++))
    fi
}

# 7. Ingress
test_ingress() {
    log_header "[7/8] Ingress Configuration"
    if [ "$NAMESPACE_EXISTS" = false ]; then
        log_warn "SKIPPED - namespace missing"
        ((SKIPPED_TESTS++))
        return
    fi
    local count
    count=$(run_cmd kubectl get ingress -n "$NAMESPACE" --no-headers | wc -l)
    if [ "$count" -gt 0 ]; then
        log_pass "Ingress configured: $count rules"
        ((PASSED_TESTS++))
    else
        log_warn "No ingress configured"
    fi
}

# 8. Warning Events
test_events() {
    log_header "[8/8] Warning Events"
    if [ "$NAMESPACE_EXISTS" = false ]; then
        log_warn "SKIPPED - namespace missing"
        ((SKIPPED_TESTS++))
        return
    fi

    local warnings
    warnings=$(run_cmd kubectl get events -n "$NAMESPACE" --field-selector type=Warning --no-headers)
    local count
    count=$(echo "$warnings" | grep -cve '^\s*$')
    if [ "$count" -eq 0 ]; then
        log_pass "No warning events"
        ((PASSED_TESTS++))
    else
        log_warn "$count warning events found"
        log_to_file "------ WARNING EVENTS ------"
        echo "$warnings" >> "$LOG_FILE"
        if [ "$count" -gt 5 ]; then
            log_fail "Too many warning events ($count)"
            ((FAILED_TESTS++))
        else
            log_info "Warning events acceptable ($count)"
            ((PASSED_TESTS++))
        fi
    fi
}

# ----------------------------
# MAIN EXECUTION
# ----------------------------
log_section "Starting SAS Viya Smoke Test Suite"

test_cluster_connectivity
test_list_namespaces
test_namespace
test_cas_controller
test_services
test_database
test_ingress
test_events

# ----------------------------
# SUMMARY
# ----------------------------
log_header "Smoke Test Complete"
log_info "Total Tests Run: 8"
log_pass "Passed: $PASSED_TESTS"
log_fail "Failed: $FAILED_TESTS"
log_warn "Skipped: $SKIPPED_TESTS"
log_to_file "SUMMARY: Passed=$PASSED_TESTS, Failed=$FAILED_TESTS, Skipped=$SKIPPED_TESTS"

echo ""
log_section "Refer to $LOG_FILE for full errors and warnings"

# Exit code
if [ "$FAILED_TESTS" -gt 0 ]; then
    exit 1
else
    exit 0
fi
