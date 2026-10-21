#!/bin/bash
# Tiny HTTP handler run by socat for each connection (loopback only, reached via nginx/ingress).
IFS= read -r line || exit 0
line=${line%$'\r'}
set -- $line
method=${1:-}
path=${2:-/}
path=${path%%\?*}
while IFS= read -r header; do
    header=${header%$'\r'}
    [ -z "$header" ] && break
done

reply() {
    printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n' "$1" "$2"
}

status() {
    if (exec 3<>/dev/tcp/127.0.0.1/1143) 2>/dev/null; then echo "Bridge IMAP is listening."; else echo "Bridge IMAP is not listening yet (not logged in, or still starting)."; fi
}

# Run `info` in the Bridge CLI (tmux session) and print its output, then clear the screen/history.
creds() {
    exec 9>/tmp/info.lock
    flock -w 10 9 || { echo "Another request is running; try again."; return; }
    tmux has-session -t bridge 2>/dev/null || { echo "Bridge CLI is not running."; return; }
    tmux clear-history -t bridge
    tmux send-keys -t bridge 'clear' Enter
    sleep 1
    tmux send-keys -t bridge 'info' Enter
    sleep 3
    tmux capture-pane -p -J -t bridge -S -100 | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -v '^[[:space:]]*$' | tail -n 40
    tmux send-keys -t bridge 'clear' Enter
    sleep 1
    tmux clear-history -t bridge
}

page() {
cat <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Proton Bridge</title>
<style>
:root{--bg:#fff;--fg:#1b1b1f;--mut:#5f6368;--card:#f3f4f7;--acc:#03a9f4}
@media (prefers-color-scheme:dark){:root{--bg:#111318;--fg:#e6e6ea;--mut:#9aa0a6;--card:#1c1f26}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;max-width:720px}
h1{font-size:1.3rem}.card{background:var(--card);border-radius:10px;padding:12px 16px;margin:12px 0}
button{background:var(--acc);color:#fff;border:0;border-radius:6px;padding:8px 14px;font-size:15px;cursor:pointer}
pre{white-space:pre-wrap;word-break:break-all;margin:8px 0 0}.mut{color:var(--mut)}code{font-family:ui-monospace,monospace}
</style></head><body>
<h1>Proton Mail Bridge</h1>
<div class="card"><strong>Status</strong><div id="status" class="mut">Checking…</div></div>
<div class="card"><strong>Bridge credentials</strong>
<p class="mut">These are the IMAP username and password Bridge generated; they are not your Proton password. They are fetched from the running Bridge only when you click and are never written to the log.</p>
<button id="show">Show Bridge credentials</button>
<pre id="out"></pre></div>
<div class="card"><strong>Home Assistant IMAP settings</strong>
<p>Server <code>local-protonmail-bridge</code>, port <code>143</code>, folder <code>INBOX</code>, <em>Verify SSL certificate</em> off. Use the username and password above.</p></div>
<p class="mut">Login and settings live on the add-on's Configuration tab. <a href="console/">Optional console</a> for CAPTCHA or security-key logins.</p>
<script>
fetch('status',{cache:'no-store'}).then(r=>r.text()).then(t=>{document.getElementById('status').textContent=t}).catch(()=>{document.getElementById('status').textContent='Status unavailable.'});
document.getElementById('show').onclick=function(){var b=this,o=document.getElementById('out');b.disabled=true;o.textContent='Reading from Bridge…';
fetch('creds',{cache:'no-store'}).then(r=>r.text()).then(t=>{o.textContent=t}).catch(()=>{o.textContent='Request failed.'}).finally(()=>{b.disabled=false})};
</script></body></html>
HTML
}

case "$method $path" in
    "GET /"|"GET /index.html") reply "200 OK" "text/html; charset=utf-8"; page ;;
    "GET /status") reply "200 OK" "text/plain; charset=utf-8"; status ;;
    "GET /creds")  reply "200 OK" "text/plain; charset=utf-8"; creds ;;
    *) reply "404 Not Found" "text/plain"; echo "not found" ;;
esac
