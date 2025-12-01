#!/bin/bash

# Setup SSH tunnels through bastion host

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../../config/environments"

# Environment parameter
ENVIRONMENT=${1:-dev}
CONFIG_FILE="${CONFIG_DIR}/${ENVIRONMENT}.yaml"

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: Configuration file ${CONFIG_FILE} not found"
    exit 1
fi

# Parse YAML config (simplified parser)
get_config_value() {
    local key=$1
    grep "^  ${key}:" "${CONFIG_FILE}" | awk '{print $2}' | head -1
}

# Get bastion configuration
BASTION_HOST=$(grep "host:" "${CONFIG_FILE}" | head -1 | awk '{print $2}')
BASTION_USER=$(grep "user:" "${CONFIG_FILE}" | head -1 | awk '{print $2}')
BASTION_KEY=$(grep "key_path:" "${CONFIG_FILE}" | head -1 | awk '{print $2}')

# Expand tilde in key path
BASTION_KEY="${BASTION_KEY/#\~/$HOME}"

echo "Setting up SSH tunnels for ${ENVIRONMENT} environment"
echo "Bastion Host: ${BASTION_USER}@${BASTION_HOST}"

# Kill existing tunnels
echo "Cleaning up existing tunnels..."
pkill -f "ssh.*${BASTION_HOST}" 2>/dev/null || true

# Setup tunnels based on config
echo "Creating SSH tunnels..."

# K8s API tunnel
ssh -i "${BASTION_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -L 6443:k8s-api-${ENVIRONMENT}.internal.example.com:443 \
    -N -f "${BASTION_USER}@${BASTION_HOST}"

echo "✓ Kubernetes API tunnel created (localhost:6443)"

# SAS Viya Web tunnel
ssh -i "${BASTION_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -L 8080:sas-viya-${ENVIRONMENT}.internal.example.com:443 \
    -N -f "${BASTION_USER}@${BASTION_HOST}"

echo "✓ SAS Viya Web tunnel created (localhost:8080)"

# CAS Controller tunnel
ssh -i "${BASTION_KEY}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -L 5570:cas-${ENVIRONMENT}.internal.example.com:5570 \
    -N -f "${BASTION_USER}@${BASTION_HOST}"

echo "✓ CAS Controller tunnel created (localhost:5570)"

# Wait for tunnels to establish
sleep 3

# Verify tunnels
echo ""
echo "Verifying tunnels..."

# Check K8s API
if nc -zv localhost 6443 2>/dev/null; then
    echo "✓ Kubernetes API tunnel is active"
else
    echo "✗ Kubernetes API tunnel failed"
    exit 1
fi

# Check SAS Viya Web
if nc -zv localhost 8080 2>/dev/null; then
    echo "✓ SAS Viya Web tunnel is active"
else
    echo "✗ SAS Viya Web tunnel failed"
    exit 1
fi

# Check CAS
if nc -zv localhost 5570 2>/dev/null; then
    echo "✓ CAS Controller tunnel is active"
else
    echo "✗ CAS Controller tunnel failed"
    exit 1
fi

echo ""
echo "All SSH tunnels established successfully!"
echo ""
echo "To use kubectl with the tunnel:"
echo "  kubectl --server=https://localhost:6443 --insecure-skip-tls-verify get nodes"
echo ""
echo "To cleanup tunnels:"
echo "  ${SCRIPT_DIR}/../teardown/cleanup-tunnels.sh"
