#!/bin/sh
# Valve's bootstrapper exits with 42 after an update to request a fresh process.
restarts=0
while :; do
    "$@"
    status=$?
    [ "$status" -eq 42 ] || exit "$status"
    restarts=$((restarts + 1))
    if [ "$restarts" -gt 2 ]; then
        echo 'Steam repeatedly requested an update restart. Stop and retry.' >&2
        exit 42
    fi
    echo 'Restarting Steam after its update...'
done
