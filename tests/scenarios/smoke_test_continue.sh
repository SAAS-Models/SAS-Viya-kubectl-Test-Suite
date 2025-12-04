#!/bin/bash

# Modified smoke test that runs ALL tests regardless of failures
# Remove the 'set -e' to prevent script from exiting on error
# set -e  # COMMENTED OUT - we want to continue even if commands fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
NAMESPACE_EXISTS=false

log_header "SAS Viya Smoke Tests - Full Run"
log_info "Namespace: ${NAMESPACE}"
log_info "Timestamp: $(date)"
log_info "Will run all 8 tests in sequence"
echo ""

# Test 1: Cluster connectivity
test_cluster_connectivity() {
    log_test "[1/8] Checking cluster connectivity"
    
    if kubectl cluster-info &>/dev/null; then
        log_pass "Cluster is accessible"
        ((PASSED_TESTS++))
    else
        log_fail "Cannot connect to cluster"
        ((FAILED_TESTS++))
    fi
}

# Test 2: List available namespaces
test_list_namespaces() {
    log_test "[2/8] Listing available namespaces"
    
    local namespaces=$(kubectl get namespaces --no-headers 2>/dev/null | awk '{print $1}')
    
    if [ ! -z "${namespaces}" ]; then
        log_info "Found namespaces:"
        echo "${namespaces}" | while read ns; do
            if [[ "${ns}" == *"sas"* ]] || [[ "${ns}" == *"viya"* ]]; then
                log_info "  → ${ns} (possible SAS Viya namespace)"
            else
                log_info "  - ${ns}"
            fi
        done
        ((PASSED_TESTS++))
    else
        log_fail "Cannot list namespaces"
        ((FAILED_TESTS++))
    fi
}

# Test 3: Namespace exists
test_namespace() {
    log_test "[3/8] Checking if namespace '${NAMESPACE}' exists"
    
    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_pass "Namespace ${NAMESPACE} exists"
        ((PASSED_TESTS++))
        NAMESPACE_EXISTS=true
    else
        log_fail "Namespace ${NAMESPACE} not found"
        ((FAILED_TESTS++))
        NAMESPACE_EXISTS=false
        log_warn "Tests 4-8 will be skipped since namespace doesn't exist"
    fi
}

# Test 4: CAS Controller
test_cas_controller() {
    log_test "[4/8] Checking CAS Controller"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local cas_pods=$(kubectl get pods -n "${NAMESPACE}" \
        -l "app.kubernetes.io/name=sas-cas-server" \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${cas_pods} -gt 0 ]]; then
        log_pass "CAS Controller found (${cas_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "CAS Controller not found"
        ((FAILED_TESTS++))
    fi
}

# Test 5: Core Services
test_core_services() {
    log_test "[5/8] Checking Core Services"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local services=("sas-logon-app" "sas-identities" "sas-authorization")
    local found=0
    local total=3
    
    for service in "${services[@]}"; do
        if kubectl get service "${service}" -n "${NAMESPACE}" &>/dev/null; then
            log_info "  ✓ ${service}"
            ((found++))
        else
            log_warn "  ✗ ${service}"
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

# Test 6: Database
test_database() {
    log_test "[6/8] Checking PostgreSQL Database"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local pg_pods=$(kubectl get pods -n "${NAMESPACE}" \
        -l "app=sas-postgres" \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${pg_pods} -gt 0 ]]; then
        log_pass "PostgreSQL running (${pg_pods} pods)"
        ((PASSED_TESTS++))
    else
        log_fail "PostgreSQL not found or not running"
        ((FAILED_TESTS++))
    fi
}

# Test 7: Ingress
test_ingress() {
    log_test "[7/8] Checking Ingress Configuration"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local ingress_count=$(kubectl get ingress -n "${NAMESPACE}" \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${ingress_count} -gt 0 ]]; then
        log_pass "Ingress configured (${ingress_count} rules)"
        ((PASSED_TESTS++))
    else
        log_warn "No ingress configured (may be optional)"
        ((PASSED_TESTS++))
    fi
}

# Test 8: Recent Events
test_events() {
    log_test "[8/8] Checking for Warning Events"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "SKIPPED - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local warnings=$(kubectl get events -n "${NAMESPACE}" \
        --field-selector type=Warning \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${warnings} -eq 0 ]]; then
        log_pass "No warning events found"
        ((PASSED_TESTS++))
    elif [[ ${warnings} -le 5 ]]; then
        log_warn "${warnings} warning events found (acceptable)"
        ((PASSED_TESTS++))
    else
        log_fail "${warnings} warning events found (too many)"
        ((FAILED_TESTS++))
    fi
}

# ============================================
# MAIN EXECUTION - RUN ALL TESTS IN SEQUENCE
# ============================================

log_section "Starting Test Suite (8 tests)"

# Run each test function explicitly
test_cluster_connectivity
echo ""  # Add spacing between tests

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

# ============================================
# FINAL SUMMARY
# ============================================

log_header "Test Execution Complete"
log_info "Total Tests Run: 8"
log_success "Passed: ${PASSED_TESTS}"
log_error "Failed: ${FAILED_TESTS}"
log_warn "Skipped: ${SKIPPED_TESTS}"

# Provide recommendations based on results
echo ""
log_section "Recommendations"

if [[ ${NAMESPACE_EXISTS} = false ]]; then
    log_warn "The namespace '${NAMESPACE}' does not exist."
    log_info "Try running with one of the namespaces listed in Test 2"
    log_info "Example: $0 <actual-namespace>"
fi

if [[ ${FAILED_TESTS} -eq 0 && ${SKIPPED_TESTS} -eq 0 ]]; then
    log_success "✓ All tests passed successfully!"
    exit 0
elif [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "✗ ${FAILED_TESTS} test(s) failed. Review the output above for details."
    exit 1
else
    log_warn "⚠ Some tests were skipped. Review the output above."
    exit 0
fi
