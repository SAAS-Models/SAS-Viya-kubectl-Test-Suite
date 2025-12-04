#!/bin/bash

# Modified smoke test that continues even if tests fail

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0
SKIPPED_TESTS=0
NAMESPACE_EXISTS=false

log_header "SAS Viya Smoke Tests"
log_info "Namespace: ${NAMESPACE}"
log_info "Timestamp: $(date)"

# Test 1: Namespace exists (modified to not exit)
test_namespace() {
    log_test "Checking namespace existence"
    if check_namespace "${NAMESPACE}"; then
        log_pass "Namespace ${NAMESPACE} exists"
        ((PASSED_TESTS++))
        NAMESPACE_EXISTS=true
    else
        log_fail "Namespace ${NAMESPACE} not found"
        ((FAILED_TESTS++))
        NAMESPACE_EXISTS=false
        log_warn "Continuing with limited tests..."
    fi
}

# Test 2: CAS Controller
test_cas_controller() {
    log_test "Checking CAS Controller"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "Skipping - namespace doesn't exist"
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

# Test 3: Core Services
test_core_services() {
    log_test "Checking Core Services"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "Skipping - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local services=("sas-logon-app" "sas-identities" "sas-authorization")
    local failed=0
    
    for service in "${services[@]}"; do
        if kubectl get service "${service}" -n "${NAMESPACE}" &>/dev/null; then
            log_info "  ✓ ${service}"
        else
            log_warn "  ✗ ${service}"
            ((failed++))
        fi
    done
    
    if [[ ${failed} -eq 0 ]]; then
        log_pass "All core services present"
        ((PASSED_TESTS++))
    else
        log_fail "${failed} core services missing"
        ((FAILED_TESTS++))
    fi
}

# Test 4: Database
test_database() {
    log_test "Checking PostgreSQL"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "Skipping - namespace doesn't exist"
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
        log_fail "PostgreSQL not running"
        ((FAILED_TESTS++))
    fi
}

# Test 5: Ingress
test_ingress() {
    log_test "Checking Ingress"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "Skipping - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local ingress_count=$(kubectl get ingress -n "${NAMESPACE}" \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${ingress_count} -gt 0 ]]; then
        log_pass "Ingress configured (${ingress_count} rules)"
        ((PASSED_TESTS++))
    else
        log_warn "No ingress configured"
        ((PASSED_TESTS++))
    fi
}

# Test 6: Recent Events
test_events() {
    log_test "Checking for warning events"
    
    if [ "${NAMESPACE_EXISTS}" = false ]; then
        log_warn "Skipping - namespace doesn't exist"
        ((SKIPPED_TESTS++))
        return
    fi
    
    local warnings=$(kubectl get events -n "${NAMESPACE}" \
        --field-selector type=Warning \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${warnings} -eq 0 ]]; then
        log_pass "No warning events"
        ((PASSED_TESTS++))
    else
        log_warn "${warnings} warning events found"
        ((PASSED_TESTS++))
    fi
}

# Test 7: Cluster connectivity
test_cluster_connectivity() {
    log_test "Checking cluster connectivity"
    
    if kubectl cluster-info &>/dev/null; then
        log_pass "Cluster is accessible"
        ((PASSED_TESTS++))
    else
        log_fail "Cannot connect to cluster"
        ((FAILED_TESTS++))
    fi
}

# Test 8: List available namespaces
test_list_namespaces() {
    log_test "Available namespaces"
    
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

# Run all tests
log_section "Running Tests"

# Always run these basic tests
test_cluster_connectivity
test_list_namespaces
test_namespace

# Run namespace-dependent tests
test_cas_controller
test_core_services
test_database
test_ingress
test_events

# Summary
log_header "Test Summary"
log_info "Passed: ${PASSED_TESTS}"
log_info "Failed: ${FAILED_TESTS}"
log_info "Skipped: ${SKIPPED_TESTS}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "All tests passed!"
    exit 0
else
    if [[ ${NAMESPACE_EXISTS} = false ]]; then
        log_error "Namespace '${NAMESPACE}' not found. Try one of the namespaces listed above."
    else
        log_error "Some tests failed!"
    fi
    exit 1
fi
