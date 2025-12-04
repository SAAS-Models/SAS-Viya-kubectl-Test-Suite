#!/bin/bash

echo "=== SMOKE TEST DEBUG VERSION ==="
echo "Testing 8 sequential tests"
echo ""

NAMESPACE=${1:-sas-viya}
COUNT=0

# Test 1
echo "[Test 1/8] Starting Test 1..."
((COUNT++))
echo "Test 1 completed"
echo ""

# Test 2
echo "[Test 2/8] Starting Test 2..."
((COUNT++))
echo "Test 2 completed"
echo ""

# Test 3
echo "[Test 3/8] Starting Test 3..."
((COUNT++))
kubectl get namespace "${NAMESPACE}" &>/dev/null && echo "Namespace exists" || echo "Namespace not found"
echo "Test 3 completed"
echo ""

# Test 4
echo "[Test 4/8] Starting Test 4..."
((COUNT++))
echo "Test 4 completed"
echo ""

# Test 5
echo "[Test 5/8] Starting Test 5..."
((COUNT++))
echo "Test 5 completed"
echo ""

# Test 6
echo "[Test 6/8] Starting Test 6..."
((COUNT++))
echo "Test 6 completed"
echo ""

# Test 7
echo "[Test 7/8] Starting Test 7..."
((COUNT++))
echo "Test 7 completed"
echo ""

# Test 8
echo "[Test 8/8] Starting Test 8..."
((COUNT++))
echo "Test 8 completed"
echo ""

echo "=== ALL TESTS COMPLETED ==="
echo "Total tests run: ${COUNT}"
