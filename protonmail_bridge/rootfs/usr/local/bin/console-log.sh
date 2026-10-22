#!/bin/bash
# Reads the Bridge console stream (tmux pipe-pane) and forwards only Bridge's own log lines to the
# add-on log. Allowlist, not a blocklist: the console also shows `info` output (the Bridge password),
# echoed 2FA codes and verification links, and none of those match the patterns below.
shopt -s extglob
esc=$'\e'
log_re='^(TRAC|DEBU|INFO|WARN|ERRO|FATA|PANI)\['
sync_re='^Sync \(([^)]*)\): ([0-9]+)(\.[0-9]+)?%'
syncmsg_re='^A sync has (begun|finished) for '
last_bucket=""

while IFS= read -r line; do
    line=${line//$esc\[*([0-9;?])[A-Za-z]/}   # colour and cursor escape codes
    line=${line//[$'\r\b']/}
    line=${line##*(>>>)*( )}                   # a prompt drawn just before the line
    line=${line//+( )/ }
    if [[ $line =~ $log_re || $line =~ $syncmsg_re ]]; then
        printf '[bridge] %s\n' "$line"
    elif [[ $line =~ $sync_re ]]; then
        # Progress is printed every second; forward it in 10% steps.
        bucket="${BASH_REMATCH[1]}:$(( ${BASH_REMATCH[2]} / 10 ))"
        if [ "$bucket" != "$last_bucket" ]; then
            last_bucket=$bucket
            printf '[bridge] %s\n' "$line"
        fi
    fi
done
