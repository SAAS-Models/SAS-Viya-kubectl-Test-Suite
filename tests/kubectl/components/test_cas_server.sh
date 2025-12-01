#!/bin/bash

# Test CAS Server components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../../lib/bash/common.sh"

NAMESPACE=${1:-sas-viya}

log_header "CAS Server Validation Tests"
log_info "Namespace: ${NAMESPACE}"

# Test CAS Controller
test_cas_controller() {
    log_test "CAS Controller Deployment"
    
    local controller_pods=$(kubectl get pods -n ${NAMESPACE} \
        -l "app.kubernetes.io/name=sas-cas-server-default-controller" \
        --no-headers 2>/dev/null)
    
    if [ -z "${controller_pods}" ]; then
        log_fail "No CAS controller pods found"
        return 1
    fi
    
    log_info "CAS Controller pods:"
    echo "${controller_pods}" | while read line; do
        local pod_name=$(echo $line | awk '{print $1}')
        local status=$(echo $line | awk '{print $3}')
        local ready=$(echo $line | awk '{print $2}')
        
        if [ "${status}" == "Running" ]; then
            log_pass "  ${pod_name}: ${status} (${ready})"
        else
            log_fail "  ${pod_name}: ${status} (${ready})"
        fi
    done
}

# Test CAS Workers
test_cas_workers() {
    log_test "CAS Worker Nodes"
    
    local worker_count=$(kubectl get pods -n ${NAMESPACE} \
        -l "app.kubernetes.io/name=sas-cas-server-default-worker" \
        --no-headers 2>/dev/null | wc -l)
    
    if [ ${worker_count} -gt 0 ]; then
        log_pass "Found ${worker_count} CAS worker nodes"
        
        kubectl get pods -n ${NAMESPACE} \
            -l "app.kubernetes.io/name=sas-cas-server-default-worker" \
            -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName \
            --no-headers | while read line; do
            log_info "  ${line}"
        done
    else
        log_warn "No CAS worker nodes found (single-node deployment?)"
    fi
}

# Test CAS Services
test_cas_services() {
    log_test "CAS Services"
    
    local services=$(kubectl get service -n ${NAMESPACE} | grep cas | head -5)
    
    if [ -z "${services}" ]; then
        log_fail "No CAS services found"
        return 1
    fi
    
    log_info "CAS Services:"
    echo "${services}" | while read line; do
        local svc_name=$(echo $line | awk '{print $1}')
        local svc_type=$(echo $line | awk '{print $2}')
        local svc_ip=$(echo $line | awk '{print $3}')
        
        if [ "${svc_name}" != "NAME" ]; then
            log_info "  ${svc_name}: Type=${svc_type}, IP=${svc_ip}"
            
            # Check endpoints
            local endpoints=$(get_service_endpoints "${svc_name}" "${NAMESPACE}")
            if [ ! -z "${endpoints}" ]; then
                log_pass "    Endpoints: ${endpoints}"
            else
                log_warn "    No endpoints available"
            fi
        fi
    done
}

# Test CAS Persistent Volumes
test_cas_storage() {
    log_test "CAS Storage (PVCs)"
    
    local cas_pvcs=$(kubectl get pvc -n ${NAMESPACE} | grep cas)
    
    if [ -z "${cas_pvcs}" ]; then
        log_warn "No CAS PVCs found"
        return 0
    fi
    
    echo "${cas_pvcs}" | while read line; do
        if [[ ! "${line}" =~ "NAME" ]]; then
            local pvc_name=$(echo $line | awk '{print $1}')
            local status=$(echo $line | awk '{print $2}')
            local volume=$(echo $line | awk '{print $3}')
            local size=$(echo $line | awk '{print $4}')
            
            if [ "${status}" == "Bound" ]; then
                log_pass "  ${pvc_name}: ${status} (${size})"
            else
                log_fail "  ${pvc_name}: ${status}"
            fi
        fi
    done
}

# Test CAS Resource Usage
test_cas_resources() {
    log_test "CAS Resource Usage"
    
    # Check if metrics server is available
    if ! kubectl top nodes &>/dev/null; then
        log_warn "Metrics server not available, skipping resource checks"
        return 0
    fi
    
    local cas_metrics=$(kubectl top pods -n ${NAMESPACE} | grep cas | head -5)
    
    if [ ! -z "${cas_metrics}" ]; then
        log_info "Top CAS pods by resource usage:"
        echo "${cas_metrics}" | while read line; do
            log_info "  ${line}"
        done
    else
        log_warn "No CAS metrics available"
    fi
}

# Test CAS ConfigMaps
test_cas_config() {
    log_test "CAS Configuration"
    
    local cas_configs=$(kubectl get configmap -n ${NAMESPACE} | grep cas | head -5)
    
    if [ -z "${cas_configs}" ]; then
        log_warn "No CAS ConfigMaps found"
        return 0
    fi
    
    log_info "CAS ConfigMaps:"
    echo "${cas_configs}" | while read line; do
        if [[ ! "${line}" =~ "NAME" ]]; then
            local cm_name=$(echo $line | awk '{print $1}')
            local data_count=$(echo $line | awk '{print $2}')
            log_info "  ${cm_name}: ${data_count} data items"
        fi
    done
}

# Run all tests
log_section "Starting CAS Server Tests"

test_cas_controller
test_cas_workers
test_cas_services
test_cas_storage
test_cas_resources
test_cas_config

log_success "CAS Server validation completed"
