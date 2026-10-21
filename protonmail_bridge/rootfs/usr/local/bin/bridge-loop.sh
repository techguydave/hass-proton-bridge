#!/bin/bash
# Runs the Bridge CLI (via upstream entrypoint "init") in the tmux session; restarts it if it exits.
while true; do
    bash /protonmail/entrypoint.sh init
    echo "Bridge CLI exited, restarting in 5 s..."
    sleep 5
done
