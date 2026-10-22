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

# This add-on's network hostname as the Supervisor knows it. It is stable across restarts and updates
# (unlike the container IP) and is what other containers, e.g. Home Assistant, must use.
addon_host() {
    local h
    h=$(cat /tmp/addon_host 2>/dev/null)
    if [ -z "$h" ] && [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        h=$(curl -fsS -m 5 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.hostname // empty' 2>/dev/null)
    fi
    [ -n "$h" ] || h=$(hostname)
    printf '%s' "$h" > /tmp/addon_host 2>/dev/null
    printf '%s' "$h"
}

# Bridge writes a debug log to rotating files (the console only ever shows warnings and errors). Each
# check with Proton for changes, every 20-40 s, logs "No new API Events" or "Received new API event".
# Only timestamps are read here; no log content leaves this function.
BRIDGE_LOGS=${BRIDGE_LOGS:-/root/.local/share/protonmail/bridge-v3/logs}

mailcheck() {
    local files key t args=()
    files=$(ls -1t "$BRIDGE_LOGS"/*.log 2>/dev/null | grep -v '_crash\.log$' | head -n 2)
    if [ -n "$files" ]; then
        # Newest lines first; keep the first (= latest) timestamp of each kind, stop once all are found.
        while IFS=$'\t' read -r key t; do
            t=$(date -d "$t" +%s 2>/dev/null) && args+=(--arg "$key" "$t")
        done < <(for f in $files; do tac "$f"; done | awk '
            function take(k) { if (!(k in got) && match($0, /time="[^"]+"/)) { got[k] = substr($0, RSTART + 6, RLENGTH - 7); n++ } }
            /msg="(No new API Events|Received new API event)/ { take("check"); take("ok") }
            /msg="Failed to get event/                        { take("check") }
            /msg="Received new API event"/                    { take("change") }
            /msg="Connection Lost, pausing"/                  { take("lost") }
            /msg="Connection Restored, resuming"/             { take("restored") }
            n >= 5 { exit }
            END { for (k in got) print k "\t" got[k] }')
    fi
    jq -n "${args[@]}" '{
        last_check: ($ARGS.named.check // null | tonumber? // null),
        last_ok_check: ($ARGS.named.ok // null | tonumber? // null),
        last_change: ($ARGS.named.change // null | tonumber? // null),
        connection_lost: ($ARGS.named.lost // null | tonumber? // null),
        connection_restored: ($ARGS.named.restored // null | tonumber? // null),
        log_found: ($ARGS.named | length > 0)
    }'
}

reply() {
    printf 'HTTP/1.1 %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n' "$1" "$2"
}

# True if something is in LISTEN state (st 0A) on local port 1143 (hex 0477).
imap_listening() {
    awk 'FNR > 1 && $2 ~ /:0477$/ && $4 == "0A" { found = 1 } END { exit !found }' \
        /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

status() {
    # Look for a listener on 1143 in the kernel socket table instead of connecting: a bare connect
    # and close makes Bridge log "IMAP server error error=EOF" on every page load.
    if imap_listening; then echo "Bridge IMAP is listening."; else echo "Bridge IMAP is not listening yet (not logged in, or still starting)."; fi
}

# Run `info` in the Bridge CLI (tmux session) and print its output, then clear the screen/history.
creds() {
    exec 9>/tmp/info.lock
    flock -w 10 9 || { echo "Another request is running; try again."; return; }
    tmux has-session -t bridge 2>/dev/null || { echo "Bridge CLI is not running."; return; }
    tmux clear-history -t bridge
    tmux send-keys -t bridge C-l
    sleep 1
    tmux send-keys -t bridge 'info' Enter
    sleep 3
    local out
    out=$(tmux capture-pane -p -J -t bridge -S -100 | sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -v '^[[:space:]]*$' | awk '/Configuration for/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}')
    # Keep only the IMAP block's address/port/username/password/security; fall back to everything.
    local trimmed
    trimmed=$(printf '%s\n' "$out" | awk '
        tolower($0) ~ /imap/ && tolower($0) !~ /(username|password|port|address|security)[[:space:]]*:/ {f=1; next}
        tolower($0) ~ /smtp/ && tolower($0) !~ /(username|password|port|address|security)[[:space:]]*:/ {f=0; next}
        f && tolower($0) ~ /(address|port|username|password|security)[[:space:]]*:/ {sub(/^[[:space:]]+/, ""); print}')
    if [ -n "$trimmed" ]; then
        # Bridge's own Address/IMAP port (127.0.0.1:1143) are internal; show how Home Assistant connects instead.
        printf 'Server:    %s\nPort:      143\n' "$(addon_host)"
        printf '%s\n' "$trimmed" | grep -viE '^(address|imap port):'
    else
        printf '%s\n' "$out"
    fi
    tmux send-keys -t bridge C-l
    sleep 1
    tmux clear-history -t bridge
}

# Proton URLs currently in the Bridge CLI output (e.g. a human-verification link); wrapped lines are rejoined.
links() {
    tmux has-session -t bridge 2>/dev/null || { echo "Bridge CLI is not running."; return; }
    tmux capture-pane -p -J -t bridge -S -300 \
        | sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
        | grep -oE 'https://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+' \
        | sed -e 's/[.,;]*$//' \
        | grep -E '^https://([a-z0-9-]+\.)*proton\.me([/?#]|$)' \
        | grep -v 'mail-api' \
        | awk '!seen[$0]++'
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
<div class="card"><strong>Mailbox sync</strong><div id="sync">Checking…</div><div id="mailcheck">Checking…</div><div id="syncerr" class="mut"></div>
<p class="mut">A full sync runs when Bridge starts, when its connection to Proton comes back, or when Proton asks for a resync. Between syncs, Bridge checks Proton for changes (new mail, read flags, moves) every 20–40 seconds; the last check and the last change come from Bridge's own log.</p></div>
<div class="card"><strong>Bridge credentials</strong>
<p class="mut">The IMAP login Bridge generated (not your Proton password), fetched only when you click.</p>
<button id="show">Show Bridge credentials</button>
<pre id="out"></pre></div>
<div class="card"><strong>Console</strong>
<p class="mut">Only needed for CAPTCHA or security-key logins. Stay on this page: leaving it closes the console connection.</p>
<iframe id="term" src="console/" title="Bridge console" style="width:100%;height:55vh;min-height:320px;border:1px solid var(--mut);border-radius:6px;background:#000"></iframe></div>
<div class="card"><strong>Verification links</strong>
<p class="mut">If Proton asks for human verification (CAPTCHA) during <code>login</code>, the link appears here automatically. Click it to open it in a new tab, complete the check, then come back to this page and continue in the console.</p>
<div id="linkout" class="mut">Watching the console…</div></div>
<div class="card"><strong>Home Assistant IMAP settings</strong>
<p>Server <code>__HOST__</code>, port <code>143</code> (not <code>127.0.0.1:1143</code>, which is only reachable inside the add-on), folder <code>INBOX</code>, <em>Verify SSL certificate</em> off. Use the username and password above.</p></div>
<p class="mut">Login and settings live on the add-on's Configuration tab.</p>
<script>
function ago(sec,now){var d=Math.max(0,Math.round(now-sec));if(d<90)return d+' s ago';if(d<5400)return Math.round(d/60)+' min ago';if(d<129600)return Math.round(d/3600)+' h ago';return Math.round(d/86400)+' days ago'}
function dur(s){s=Math.max(0,Math.round(s));if(s<90)return s+' s';if(s<5400)return Math.round(s/60)+' min';return (s/3600).toFixed(1)+' h'}
function when(sec){return new Date(sec*1000).toLocaleString()}
function syncText(d,now){
  var r={main:'No sync recorded yet. It appears here the next time Bridge syncs.',err:''};
  var retrying=d&&d.state==='syncing'&&d.last_error&&d.started&&d.last_error.time>=d.started&&/Failed to sync/.test(d.last_error.text);
  if(retrying){r.main='The sync of '+(d.account||'')+' is retrying after an error (Bridge retries every 20 s); '+(d.percent!=null?d.percent:0)+'% done so far, started '+when(d.started)+'.'}
  else if(d&&d.state==='syncing'){var eta=d.eta&&/^[0-9.]+s$/.test(d.eta)?' · about '+dur(parseFloat(d.eta))+' left':'';
    r.main='Syncing '+(d.account||'')+': '+(d.percent!=null?d.percent:0)+'%'+eta+(d.started?' · started '+when(d.started):'')+'. Mail apps see only part of the mailbox until it finishes.'}
  else if(d&&d.state==='finished'&&d.finished){r.main='Last full sync finished '+when(d.finished)+' ('+ago(d.finished,now)+')'+(d.started?', took '+dur(d.finished-d.started):'')+'.'}
  else if(d&&d.state==='interrupted'){r.main='The last sync'+(d.started?' (started '+when(d.started)+')':'')+' was interrupted by a restart at '+(d.percent!=null?d.percent:0)+'%. Bridge syncs again after it starts.'}
  if(d&&d.last_error){r.err='Last Bridge error, '+when(d.last_error.time)+' ('+ago(d.last_error.time,now)+'): '+d.last_error.text}
  return r}
function refreshSync(){if(document.hidden)return;
  fetch('sync',{cache:'no-store'}).then(r=>r.json()).then(function(d){var t=syncText(d,Date.now()/1000);
    document.getElementById('sync').textContent=t.main;document.getElementById('syncerr').textContent=t.err})
  .catch(function(){document.getElementById('sync').textContent='Sync status unavailable.'})}
refreshSync();setInterval(refreshSync,10000);
function mailcheckText(m,now){
  if(!m||!m.log_found)return 'No checks with Proton found in Bridge\'s log yet.';
  if(m.connection_lost&&(!m.connection_restored||m.connection_lost>m.connection_restored))
    return 'Bridge lost its connection to Proton '+ago(m.connection_lost,now)+' and has paused mail checks until it comes back.';
  if(!m.last_check)return 'No checks with Proton found in Bridge\'s log yet.';
  var t;
  if(now-m.last_check>180)t='No check with Proton for '+dur(now-m.last_check)+' (normally every 20–40 s).';
  else t='Last check with Proton '+ago(m.last_check,now)+(m.last_ok_check===m.last_check?'':' (failed; Bridge retries automatically)')+'.';
  if(m.last_change)t+=' Last change from Proton: '+when(m.last_change)+' ('+ago(m.last_change,now)+').';
  return t}
function refreshMailcheck(){if(document.hidden)return;
  fetch('mailcheck',{cache:'no-store'}).then(r=>r.json()).then(function(m){document.getElementById('mailcheck').textContent=mailcheckText(m,Date.now()/1000)})
  .catch(function(){document.getElementById('mailcheck').textContent='Mail check status unavailable.'})}
refreshMailcheck();setInterval(refreshMailcheck,30000);
fetch('status',{cache:'no-store'}).then(r=>r.text()).then(t=>{document.getElementById('status').textContent=t}).catch(()=>{document.getElementById('status').textContent='Status unavailable.'});
document.getElementById('show').onclick=function(){var b=this,o=document.getElementById('out');b.disabled=true;o.textContent='Reading from Bridge…';
fetch('creds',{cache:'no-store'}).then(r=>r.text()).then(t=>{o.textContent=t}).catch(()=>{o.textContent='Request failed.'}).finally(()=>{b.disabled=false})};
function refreshLinks(){if(document.hidden)return;var o=document.getElementById('linkout');
fetch('links',{cache:'no-store'}).then(r=>r.text()).then(function(t){var items=[];
t.split('\n').forEach(function(l){l=l.trim();if(!l)return;var u;try{u=new URL(l)}catch(e){return}
if(u.protocol!=='https:'||!(u.hostname==='proton.me'||u.hostname.endsWith('.proton.me')))return;items.push(u.href)});
var key=items.join('\n');if(o.dataset.key===key)return;o.dataset.key=key;o.textContent='';
if(!items.length){o.className='mut';o.textContent='No Proton links in the console yet.';return}
o.className='';items.forEach(function(h){var d=document.createElement('div'),a=document.createElement('a');a.href=h;a.target='_blank';a.rel='noopener noreferrer';a.textContent=h;a.style.wordBreak='break-all';d.appendChild(a);o.appendChild(d)})}).catch(function(){})}
refreshLinks();setInterval(refreshLinks,4000);
</script></body></html>
HTML
}

case "$method $path" in
    "GET /"|"GET /index.html") reply "200 OK" "text/html; charset=utf-8"; page | sed "s/__HOST__/$(addon_host)/g" ;;
    "GET /status") reply "200 OK" "text/plain; charset=utf-8"; status ;;
    "GET /mailcheck") reply "200 OK" "application/json"; mailcheck ;;
    "GET /sync")   reply "200 OK" "application/json"; cat "${SYNC_STATE:-/data/sync_status.json}" 2>/dev/null || echo '{}' ;;
    "GET /links")  reply "200 OK" "text/plain; charset=utf-8"; links ;;
    "GET /creds")  reply "200 OK" "text/plain; charset=utf-8"; creds ;;
    *) reply "404 Not Found" "text/plain"; echo "not found" ;;
esac
