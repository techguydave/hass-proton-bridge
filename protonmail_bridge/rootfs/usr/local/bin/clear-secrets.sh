#!/bin/bash
# Remove one-time login secrets from the add-on options via the Supervisor API.
set -u
opts=$(jq -c 'del(.password, .mailbox_password, .two_factor_code)' /data/options.json) || exit 1
if curl -fsS -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"options\": ${opts}}" \
        http://supervisor/addons/self/options >/dev/null; then
    echo "Cleared one-time login secrets from the add-on options."
else
    echo "WARNING: could not clear login secrets from the options; blank them manually." >&2
fi
