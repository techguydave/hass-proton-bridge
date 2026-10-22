#!/bin/bash
set -u
OPTIONS=/data/options.json
opt() { jq -r --arg k "$1" '.[$k] // empty' "$OPTIONS"; }

mkdir -p /data/home
chmod 700 /data/home
export HOME=/root

export PB_USERNAME="$(opt username)"
export PB_PASSWORD="$(opt password)"
export PB_MAILBOX_PASSWORD="$(opt mailbox_password)"
export PB_2FA="$(opt two_factor_code)"
export PB_IMAP_SECURITY="$(opt imap_security)"

# --- one-time login / settings, before the long-running Bridge starts -------------
if [ -n "$PB_USERNAME" ] && [ -n "$PB_PASSWORD" ]; then
    echo "Attempting Proton login for ${PB_USERNAME}..."
    result=$(/usr/local/bin/login.exp login 2>&1 | tr -d '\000')
    echo "$result" | tail -n 40
    /usr/local/bin/clear-secrets.sh
elif [ -d /root/.password-store ] && [ -n "$PB_IMAP_SECURITY" ]; then
    result=$(/usr/local/bin/login.exp settings 2>&1 | tr -d '\000')
    if echo "$result" | grep -qE '^(LOGIN_FAIL|IMAP_SECURITY_FAIL)'; then
        echo "$result" | tail -n 40
    else
        echo "$result" | grep -E '^IMAP_SECURITY' || { echo "IMAP_SECURITY: no result from settings run; output follows"; echo "$result" | tail -n 40; }
    fi
fi
unset PB_PASSWORD PB_MAILBOX_PASSWORD PB_2FA

# --- disable Bridge's self-updater once (mirrors upstream entrypoint) -------------
if [ -d /root/.password-store ] && [ ! -f /root/.autoupdate-disabled ]; then
    if printf 'updates autoupdates disable\nyes\n' | timeout 60 /protonmail/proton-bridge --cli >/dev/null 2>&1; then
        touch /root/.autoupdate-disabled
    fi
fi

# --- long-running services ---------------------------------------------------------
socat TCP-LISTEN:25,fork,reuseaddr TCP:127.0.0.1:1025 &
SOCAT_SMTP=$!
socat TCP-LISTEN:143,fork,reuseaddr TCP:127.0.0.1:1143 &
SOCAT_IMAP=$!

cp /etc/tmux.conf /root/.tmux.conf 2>/dev/null || true
tmux new-session -d -s bridge /usr/local/bin/bridge-loop.sh
# Watch the console: console-log.sh records the mailbox sync state for the status page and, unless
# turned off, forwards Bridge's own log lines (filtered allowlist) to the add-on log. The reader is a
# child of this script, so it writes to the add-on log; it reopens the FIFO whenever the writer goes away.
export SYNC_STATE=/data/sync_status.json
if [ -f "$SYNC_STATE" ] && [ "$(jq -r '.state' "$SYNC_STATE" 2>/dev/null)" = syncing ]; then
    jq '.state = "interrupted"' "$SYNC_STATE" > "$SYNC_STATE.tmp" && mv -f "$SYNC_STATE.tmp" "$SYNC_STATE"
fi
if [ "$(jq -r '.forward_console_logs' "$OPTIONS")" = "false" ]; then export FORWARD_LOGS=0; else export FORWARD_LOGS=1; fi
rm -f /tmp/console.fifo
mkfifo -m 600 /tmp/console.fifo
( while true; do /usr/local/bin/console-log.sh < /tmp/console.fifo; done ) &
tmux pipe-pane -o -t bridge 'exec cat >> /tmp/console.fifo'
ttyd -i 127.0.0.1 -p 7681 -b /console -W tmux attach -t bridge &
TTYD=$!
socat TCP-LISTEN:8100,bind=127.0.0.1,fork,reuseaddr EXEC:/usr/local/bin/web.sh &
WEB=$!
nginx -c /etc/nginx/nginx.conf &
NGINX=$!
echo "Proton Bridge add-on started (IMAP 143 / SMTP 25 on the internal network only)."

while kill -0 "$SOCAT_SMTP" "$SOCAT_IMAP" "$TTYD" "$WEB" "$NGINX" 2>/dev/null \
        && tmux has-session -t bridge 2>/dev/null; do
    sleep 5
done
echo "A supervised process exited; stopping so Supervisor restarts the add-on." >&2
exit 1
