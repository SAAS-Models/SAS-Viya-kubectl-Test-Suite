#!/bin/bash

# Smoke test for SAS Viya deployment
# Quick validation of critical components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/bash/common.sh"

NAMESPACE=${1:-sas-viya}
FAILED_TESTS=0
PASSED_TESTS=0

log_header "SAS Viya Smoke Tests"
log_info "Namespace: ${NAMESPACE}"
log_info "Timestamp: $(date)"

# Test 1: Namespace exists
test_namespace() {
    log_test "Checking namespace existence"
    if check_namespace "${NAMESPACE}"; then
        log_pass "Namespace ${NAMESPACE} exists"
        ((PASSED_TESTS++))
    else
        log_fail "Namespace ${NAMESPACE} not found"
        ((FAILED_TESTS++))
        exit 1
    fi
}

# Test 2: CAS Controller
test_cas_controller() {
    log_test "Checking CAS Controller"
    
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
    
    local ingress_count=$(kubectl get ingress -n "${NAMESPACE}" \
        --no-headers 2>/dev/null | wc -l)
    
    if [[ ${ingress_count} -gt 0 ]]; then
        log_pass "Ingress configured (${ingress_count} rules)"
        ((PASSED_TESTS++))
    else
        log_warn "No ingress configured"
        # Not failing as ingress might not be required
        ((PASSED_TESTS++))
    fi
}

# Test 6: Recent Events
test_events() {
    log_test "Checking for warning events"
    
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

# Run all tests
log_section "Running Tests"
test_namespace
test_cas_controller
test_core_services
test_database
test_ingress
test_events

# Summary
log_header "Test Summary"
log_info "Passed: ${PASSED_TESTS}"
log_info "Failed: ${FAILED_TESTS}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "All smoke tests passed!"
    exit 0
else
    log_error "Some tests failed!"
    exit 1
fi
