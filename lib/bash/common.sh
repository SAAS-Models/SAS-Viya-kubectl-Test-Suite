#!/bin/bash

# Common functions for kubectl tests

# Source other libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/colors.sh"
source "${SCRIPT_DIR}/logging.sh"

# Global variables
NAMESPACE="${NAMESPACE:-sas-viya}"
TIMEOUT="${TIMEOUT:-300}"
KUBECTL_CMD="${KUBECTL_CMD:-kubectl}"

# Function to check if kubectl is configured
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl is not configured or cluster is not accessible"
        return 1
    fi
    
    return 0
}

# Function to check if namespace exists
check_namespace() {
    local namespace=$1
    if kubectl get namespace "${namespace}" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to wait for pod to be ready
wait_for_pod() {
    local pod_label=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log_info "Waiting for pod with label ${pod_label} to be ready..."
    
    kubectl wait --for=condition=ready pod \
        -l "${pod_label}" \
        -n "${namespace}" \
        --timeout="${timeout}s"
}

# Function to get pod status
get_pod_status() {
    local pod_name=$1
    local namespace=$2
    
    kubectl get pod "${pod_name}" \
        -n "${namespace}" \
        -o jsonpath='{.status.phase}'
}

# Function to check deployment status
check_deployment() {
    local deployment=$1
    local namespace=$2
    
    local ready=$(kubectl get deployment "${deployment}" \
        -n "${namespace}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    
    local desired=$(kubectl get deployment "${deployment}" \
        -n "${namespace}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    
    if [[ -z "${ready}" ]] || [[ -z "${desired}" ]]; then
        return 1
    fi
    
    if [[ "${ready}" -eq "${desired}" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to get service endpoints
get_service_endpoints() {
    local service=$1
    local namespace=$2
    
    kubectl get endpoints "${service}" \
        -n "${namespace}" \
        -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null
}

# Function to check if PVC is bound
check_pvc_bound() {
    local pvc=$1
    local namespace=$2
    
    local status=$(kubectl get pvc "${pvc}" \
        -n "${namespace}" \
        -o jsonpath='{.status.phase}' 2>/dev/null)
    
    [[ "${status}" == "Bound" ]]
}

# Function to get recent events
get_recent_events() {
    local namespace=$1
    local event_type=${2:-Warning}
    
    kubectl get events -n "${namespace}" \
        --field-selector type="${event_type}" \
        --sort-by='.lastTimestamp' \
        -o custom-columns=TIME:.lastTimestamp,NAMESPACE:.involvedObject.namespace,NAME:.involvedObject.name,REASON:.reason,MESSAGE:.message \
        --no-headers | tail -10
}

# Export functions
export -f check_kubectl
export -f check_namespace
export -f wait_for_pod
export -f get_pod_status
export -f check_deployment
export -f get_service_endpoints
export -f check_pvc_bound
export -f get_recent_events
