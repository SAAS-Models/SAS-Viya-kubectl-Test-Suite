#!/bin/bash

# Cleanup SSH tunnels

echo "Cleaning up SSH tunnels..."

# Find and kill SSH tunnel processes
SSH_PIDS=$(ps aux | grep -E "ssh.*-L.*:.*:.*-N -f" | grep -v grep | awk '{print $2}')

if [ -z "${SSH_PIDS}" ]; then
    echo "No SSH tunnels found"
else
    for PID in ${SSH_PIDS}; do
        echo "Killing SSH tunnel process: ${PID}"
        kill ${PID} 2>/dev/null || true
    done
    echo "SSH tunnels cleaned up"
fi

# Also cleanup by port
for PORT in 6443 8080 5570; do
    PID=$(lsof -ti:${PORT} 2>/dev/null)
    if [ ! -z "${PID}" ]; then
        echo "Killing process on port ${PORT}: ${PID}"
        kill ${PID} 2>/dev/null || true
    fi
done

echo "Cleanup complete"
