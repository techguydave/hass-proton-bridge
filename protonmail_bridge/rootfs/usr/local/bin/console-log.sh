#!/bin/bash
# Reads the Bridge console stream (tmux pipe-pane) and
#  - records the mailbox sync state in $SYNC_STATE (shown on the status page), and
#  - if FORWARD_LOGS=1, forwards Bridge's own log lines to the add-on log.
# Both use an allowlist, not a blocklist: the console also shows `info` output (the Bridge password),
# echoed 2FA codes and verification links, and none of those match the patterns below.
shopt -s extglob
SYNC_STATE=${SYNC_STATE:-/data/sync_status.json}
FORWARD_LOGS=${FORWARD_LOGS:-1}
esc=$'\e'
log_re='^(TRAC|DEBU|INFO|WARN|ERRO|FATA|PANI)\['
err_re='^(ERRO|FATA|PANI)\[[^]]*\] *(.*)$'
sync_re='^Sync \(([^)]*)\): ([0-9]+)(\.[0-9]+)?%'
eta_re='ETA: ([^,)]*)'
begun_re='^A sync has begun for (.*)\.$'
finished_re='^A sync has finished for (.*)\.$'

account="" state="" percent="" eta="" started="" finished="" err_time="" err_text=""
if [ -f "$SYNC_STATE" ]; then
    # Unit separator, not tab: bash merges runs of whitespace separators, which would shift fields
    # after an empty one.
    IFS=$'\x1f' read -r account state percent eta started finished err_time err_text < <(jq -r '[
        (.account // ""), (.state // ""), ((.percent // "") | tostring), (.eta // ""),
        ((.started // "") | tostring), ((.finished // "") | tostring),
        ((.last_error.time // "") | tostring), (.last_error.text // "")] | join("\u001f")' "$SYNC_STATE" 2>/dev/null)
fi
last_pct_int=""
last_bucket=""

save() {
    jq -n --arg account "$account" --arg state "$state" --arg percent "$percent" --arg eta "$eta" \
        --arg started "$started" --arg finished "$finished" --arg updated "$(date +%s)" \
        --arg err_time "$err_time" --arg err_text "$err_text" '{
            account: $account, state: $state,
            percent: ($percent | tonumber? // null), eta: (if $eta == "" then null else $eta end),
            started: ($started | tonumber? // null), finished: ($finished | tonumber? // null),
            updated: ($updated | tonumber),
            last_error: (if $err_time == "" then null else {time: ($err_time | tonumber), text: $err_text} end)
        }' > "$SYNC_STATE.tmp" 2>/dev/null && mv -f "$SYNC_STATE.tmp" "$SYNC_STATE"
}

forward() { [ "$FORWARD_LOGS" = 1 ] && printf '[bridge] %s\n' "$1"; }

while IFS= read -r line; do
    line=${line//$esc\[*([0-9;?])[A-Za-z]/}   # colour and cursor escape codes
    line=${line//[$'\r\b']/}
    line=${line##*(>>>)*( )}                   # a prompt drawn just before the line
    line=${line//+( )/ }
    line=${line%% }

    if [[ $line =~ $begun_re ]]; then
        account=${BASH_REMATCH[1]} state=syncing percent=0 eta="" started=$(date +%s)
        last_pct_int=0
        save; forward "$line"
    elif [[ $line =~ $finished_re ]]; then
        account=${BASH_REMATCH[1]} state=finished percent=100 eta="" finished=$(date +%s)
        [ -n "$started" ] || started=$finished
        save; forward "$line"
    elif [[ $line =~ $sync_re ]]; then
        account=${BASH_REMATCH[1]}
        pct_int=${BASH_REMATCH[2]}
        percent="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        if [[ $line =~ $eta_re ]]; then eta=${BASH_REMATCH[1]}; else eta=""; fi
        # Progress without a "begun" line (e.g. the reader started mid-sync): start the clock now.
        if [ "$state" != syncing ]; then state=syncing; started=$(date +%s); fi
        # Progress is printed every second: save when the whole percentage changes, log every 10%.
        if [ "$pct_int" != "$last_pct_int" ]; then last_pct_int=$pct_int; save; fi
        bucket="$account:$(( pct_int / 10 ))"
        if [ "$bucket" != "$last_bucket" ]; then last_bucket=$bucket; forward "$line"; fi
    elif [[ $line =~ $log_re ]]; then
        if [[ $line =~ $err_re ]]; then
            err_time=$(date +%s) err_text=${BASH_REMATCH[2]:0:300}
            save
        fi
        forward "$line"
    fi
done
