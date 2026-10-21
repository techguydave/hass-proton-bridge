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
    result=$(/usr/local/bin/login.exp login 2>&1)
    echo "$result" | tail -n 40
    /usr/local/bin/clear-secrets.sh
elif [ -d /root/.password-store ] && [ -n "$PB_IMAP_SECURITY" ]; then
    result=$(/usr/local/bin/login.exp settings 2>&1)
    echo "$result" | grep -E '^(LOGIN_FAIL|IMAP_SECURITY_SET)' || true
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
