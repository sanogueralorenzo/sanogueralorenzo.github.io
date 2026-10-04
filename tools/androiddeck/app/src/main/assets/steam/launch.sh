#!/bin/sh
# Valve's bootstrapper exits with 42 after an update to request a fresh process.
restarts=0
while :; do
    "$@"
    status=$?
    [ "$status" -eq 42 ] || break
    restarts=$((restarts + 1))
    if [ "$restarts" -gt 2 ]; then
        echo 'Steam repeatedly requested an update restart. Stop and retry.' >&2
        break
    fi
    echo 'Restarting Steam after its update...'
done
# Gamescope does not propagate its child's status. Record Steam's final result
# in the private session directory before the compositor exits.
printf '%s\n' "$status" > /run/androiddeck/steam-exit || exit 1
exit "$status"
