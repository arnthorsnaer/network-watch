#!/usr/bin/env bash
# network-watch.sh — terminal UI for Network Watch
# Starts network-watchd if not running, then shows a live heatmap.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="$SCRIPT_DIR/network-watchd"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    echo ""; echo "Setup needed: .env is missing from $SCRIPT_DIR"; echo ""; exit 1
fi
source "$SCRIPT_DIR/.env"
EMAIL_ENABLED=0; [[ -n "${ALERT_EMAIL:-}" ]] && EMAIL_ENABLED=1

MACHINE_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
APP_SUPPORT="$HOME/Library/Application Support/NetworkWatch"
DATA_FILE="$APP_SUPPORT/checks.csv"
STATUS_FILE="$APP_SUPPORT/status"
LAST_EMAIL_FILE="$APP_SUPPORT/last-email.txt"
STATE_DIR="/tmp/network-watch"
PID_FILE="$STATE_DIR/daemon.pid"
DISPLAY_MODE=minute

# ── Daemon management ─────────────────────────────────────────────────────────

start_daemon_if_needed() {
    mkdir -p "$STATE_DIR" "$APP_SUPPORT"
    if [[ -f "$PID_FILE" ]]; then
        local pid; pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then return; fi
        rm -f "$PID_FILE"
    fi
    "$DAEMON" &
    DAEMON_PID=$!
}

stop_daemon() {
    [[ -n "${DAEMON_PID:-}" ]] && kill "$DAEMON_PID" 2>/dev/null || true
}

# Reads the status file written by the daemon into G_ globals
read_status() {
    G_SSID="" G_WIFI_IFACE="" G_GATEWAY="" G_GW_LOSS=0 G_NET_LOSS=0
    G_DNS_SYS="" G_HTTPS="0"
    LAST_STATE="OK" LAST_CHECKED=""
    [[ -f "$STATUS_FILE" ]] || return
    local line key val
    while IFS= read -r line; do
        key="${line%%=*}"; val="${line#*=}"
        case "$key" in
            checked_at) LAST_CHECKED="$val" ;;
            state)      LAST_STATE="$val"   ;;
            ssid)       G_SSID="$val"       ;;
            wifi_iface) G_WIFI_IFACE="$val" ;;
            gateway)    G_GATEWAY="$val"    ;;
            gw_loss)    G_GW_LOSS="${val:-0}"  ;;
            net_loss)   G_NET_LOSS="${val:-0}" ;;
            dns_sys)    G_DNS_SYS="$val"    ;;
            https)      G_HTTPS="$val"      ;;
        esac
    done < "$STATUS_FILE"
}

# ── UI ────────────────────────────────────────────────────────────────────────

_GN='\033[38;2;57;211;83m'
_YL='\033[38;2;214;168;0m'
_RD='\033[38;2;218;54;51m'
_RS='\033[0m'
_BD='\033[1m'
_DM='\033[2m'

_cell_bg() {
    local rate=$1 r g b t
    if (( rate < 0 )); then printf '\033[48;2;48;54;61m'; return; fi
    if (( rate >= 50 )); then
        t=$(( (rate - 50) * 2 ))
        r=$(( 214 - 157 * t / 100 ))
        g=$(( 168 +  43 * t / 100 ))
        b=$((        83 * t / 100 ))
    else
        t=$(( rate * 2 ))
        r=$(( 218 -   4 * t / 100 ))
        g=$(( 54  + 114 * t / 100 ))
        b=$(( 51  -  51 * t / 100 ))
    fi
    printf '\033[48;2;%d;%d;%dm' $r $g $b
}

_dot() {
    local ok=$1 loss=${2:-0}
    if   (( ok == 0 ));    then printf "${_RD}●${_RS}"
    elif (( loss >= 15 )); then printf "${_YL}●${_RS}"
    else                        printf "${_GN}●${_RS}"
    fi
}

draw_ui() {
    local state="$1" checked_at="$2"
    local mode="${DISPLAY_MODE:-minute}"
    local lw=9

    local now_ep; now_ep=$(date +%s)
    local num_buckets bucket_size win_start win_end cell_w label_every left_label

    case "$mode" in
        minute) num_buckets=60; bucket_size=60;    cell_w=1; label_every=15; left_label="60m ago" ;;
        hour)   num_buckets=24; bucket_size=3600;  cell_w=2; label_every=4;  left_label="24h ago" ;;
        day)    num_buckets=30; bucket_size=86400; cell_w=2; label_every=7;  left_label="30d ago" ;;
    esac
    win_end=$now_ep
    win_start=$(( win_end - num_buckets * bucket_size ))

    local raw
    raw=$(awk -v ws="$win_start" -v we="$win_end" \
        -v bsize="$bucket_size" -v nb="$num_buckets" \
    'BEGIN{FS=","}
    /^[0-9]/{
        e=$1+0; if(e<ws||e>=we)next
        b=int((e-ws)/bsize); if(b<0||b>=nb)next
        for(c=1;c<=5;c++){k=b"_"c;tot[k]++;if($(c+1)+0==1)ok[k]++}
        bk="b_"b; bt[bk]++
        if($2+0==1&&$3+0==1&&$4+0==1&&$5+0==1&&$6+0==1)bo[bk]++
    }
    END{
        for(b=0;b<nb;b++){bk="b_"b
            if(bk in bt) printf "%d",int(bo[bk]*100/bt[bk])
            else printf "-1"
            printf (b<nb-1)?",":"\n"
        }
        for(c=1;c<=5;c++){
            for(b=0;b<nb;b++){k=b"_"c
                printf (k in tot)?int(ok[k]*100/tot[k]):"-1"
                printf (b<nb-1)?",":"\n"
            }
        }
        print "---"
        inc=0
        for(b=0;b<nb;b++){bk="b_"b
            if(bk in bt&&bo[bk]*100/bt[bk]<80)inc++
        }
        print inc
    }' "$DATA_FILE" 2>/dev/null) || true

    local rows=() incidents=0 in2=0
    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then in2=1; continue; fi
        (( in2 )) && incidents=$line || rows+=("$line")
    done <<< "$raw"

    local ndr="-1"
    for _ in $(seq 2 $num_buckets); do ndr="$ndr,-1"; done
    while (( ${#rows[@]} < 6 )); do rows+=("$ndr"); done

    local hdr=""
    if [[ "$mode" == "minute" ]]; then
        hdr=$(printf '%*s' $num_buckets '')
        for pos in 0 15 30 45; do
            local lbl; lbl=$(date -r $(( win_start + pos * bucket_size )) '+%H:%M' 2>/dev/null || echo '??:??')
            hdr="${hdr:0:$pos}${lbl}${hdr:$(( pos + 5 ))}"
        done
    else
        for (( b=0; b<num_buckets; b++ )); do
            if (( b % label_every == 0 )); then
                local lbl_ep=$(( win_start + b * bucket_size ))
                if [[ "$mode" == "hour" ]]; then
                    hdr+="$(date -r $lbl_ep '+%H' 2>/dev/null)"
                else
                    hdr+="$(date -r $lbl_ep '+%d' 2>/dev/null)"
                fi
            else
                hdr+="$(printf '%*s' $cell_w '')"
            fi
        done
    fi

    local data_width=$(( num_buckets * cell_w ))
    printf '\033[2J\033[H'

    local term_w; term_w=$(tput cols 2>/dev/null || echo 80)
    local dstr; dstr=$(date '+%a %d %b, %H:%M')
    local title_plain="  Network Watch — ${MACHINE_NAME}"
    printf "  ${_BD}Network Watch — %s${_RS}" "$MACHINE_NAME"
    printf '%*s%s\n' $(( term_w - ${#title_plain} - ${#dstr} )) '' "$dstr"
    echo

    for m in minute hour day; do
        if [[ "$m" == "$mode" ]]; then
            printf "${_BD}[${m:0:1}] ${m}${_RS}  "
        else
            printf "${_DM}[${m:0:1}] ${m}${_RS}  "
        fi
    done
    if (( EMAIL_ENABLED )); then
        printf "  ${_DM}[l] send log by email${_RS}"
    fi
    echo; echo

    # ── Current Status ────────────────────────────────────────────────────────
    printf '  ── Current Status '; printf '─%.0s' $(seq 1 51); echo
    echo

    local wifi_ok=0 gw_ok=0 net_ok=0 dns_ok=0 web_ok=0
    [[ -n "$G_SSID" ]]    && wifi_ok=1
    (( G_GW_LOSS  < 20 )) && gw_ok=1  || true
    (( G_NET_LOSS < 20 )) && net_ok=1 || true
    [[ -n "$G_DNS_SYS" ]] && dns_ok=1
    [[ "$G_HTTPS" == "200" || "$G_HTTPS" == "301" || "$G_HTTPS" == "302" ]] && web_ok=1

    local failing=$(( (1-wifi_ok) + (1-gw_ok) + (1-net_ok) + (1-dns_ok) + (1-web_ok) ))
    if (( failing == 0 )); then
        printf '    %-12s %s  All systems operational\n' "Overall" "$(_dot 1)"
    elif (( failing == 1 )); then
        printf '    %-12s %s  1 check failing\n' "Overall" "$(_dot 0)"
    else
        printf '    %-12s %s  %d checks failing\n' "Overall" "$(_dot 0)" $failing
    fi
    echo

    if [[ -n "$G_SSID" ]]; then
        printf '    %-12s %s  Connected\n' "WiFi" "$(_dot $wifi_ok)"
    elif [[ -n "$G_WIFI_IFACE" ]]; then
        printf '    %-12s %s  Not connected\n' "WiFi" "$(_dot 0)"
    else
        printf '    %-12s %s  No adapter\n' "WiFi" "$(_dot 0)"
    fi
    if (( gw_ok )); then
        printf '    %-12s %s  Reachable — %s  (%d%% loss)\n' \
            "Router" "$(_dot $gw_ok $G_GW_LOSS)" "${G_GATEWAY:-(unknown)}" $G_GW_LOSS
    else
        printf '    %-12s %s  Not reachable — %s  (%d%% loss)\n' \
            "Router" "$(_dot 0)" "${G_GATEWAY:-(unknown)}" $G_GW_LOSS
    fi
    if (( net_ok )); then
        printf '    %-12s %s  Reachable  (%d%% loss)\n' \
            "Internet" "$(_dot $net_ok $G_NET_LOSS)" $G_NET_LOSS
    else
        printf '    %-12s %s  Not reachable  (%d%% loss)\n' \
            "Internet" "$(_dot 0)" $G_NET_LOSS
    fi
    if (( dns_ok )); then
        printf '    %-12s %s  Operational\n' "DNS" "$(_dot 1)"
    else
        printf '    %-12s %s  Failed\n' "DNS" "$(_dot 0)"
    fi
    if (( web_ok )); then
        printf '    %-12s %s  Web access OK\n' "Web" "$(_dot 1)"
    else
        printf '    %-12s %s  Web access failed\n' "Web" "$(_dot 0)"
    fi

    if [[ -z "$checked_at" ]]; then
        echo; printf "    ${_DM}Waiting for first check...${_RS}\n"
    else
        echo; printf '    Checked at %s\n' "$checked_at"
    fi
    echo
    printf '  '; printf '─%.0s' $(seq 1 69); echo
    echo

    # ── Heatmap ───────────────────────────────────────────────────────────────
    printf '  %*s %s\n' $lw '' "$hdr"
    local cnames=("Overall" "WiFi" "Router" "Internet" "DNS" "Web")
    for (( c=0; c<6; c++ )); do
        printf "  ${_BD}%-*s${_RS} " $lw "${cnames[$c]}"
        local old_ifs="$IFS"; IFS=',' read -ra rates <<< "${rows[$c]}"; IFS="$old_ifs"
        for rate in "${rates[@]}"; do
            _cell_bg "$rate"; printf '%*s' $cell_w ''; printf "$_RS"
        done
        echo
        if (( c == 0 )); then
            printf '  %*s ' $lw ''; printf '·%.0s' $(seq 1 $data_width); echo
        fi
    done
    printf '  %*s ' $lw ''; printf '←'; printf '─%.0s' $(seq 1 $(( data_width - 2 ))); printf '→'; echo
    printf '  %*s %-*s%s\n' $lw '' $(( data_width - 3 )) "$left_label" 'now'
    echo

    if   (( incidents == 0 )); then printf '  No incidents in this window'
    elif (( incidents == 1 )); then printf "  ${_BD}1 incident${_RS} in this window"
    else                             printf "  ${_BD}%d incidents${_RS} in this window" "$incidents"
    fi
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
        local last_sent="never"
        if [[ -f "$LAST_EMAIL_FILE" ]]; then
            local raw_ts today
            raw_ts=$(cat "$LAST_EMAIL_FILE"); today=$(date '+%Y-%m-%d')
            [[ "$raw_ts" == "$today"* ]] && last_sent="today at ${raw_ts#* }" || last_sent="$raw_ts"
        fi
        printf "  |  Email: ${_BD}%s${_RS} (last sent: %s)" "$ALERT_EMAIL" "$last_sent"
    else
        printf "  |  ${_DM}Email: not configured${_RS}"
    fi
    echo; echo
}

run_countdown() {
    local seconds=$1 last_state="$2" last_checked="$3"
    for (( i=seconds; i>0; i-- )); do
        printf '  Next check in %ds...   \r' $i
        local key=""
        if read -s -n1 -t1 key 2>/dev/null; then
            case "$key" in
                m) DISPLAY_MODE=minute; read_status; draw_ui "$LAST_STATE" "$LAST_CHECKED"; i=$seconds ;;
                h) DISPLAY_MODE=hour;   read_status; draw_ui "$LAST_STATE" "$LAST_CHECKED"; i=$seconds ;;
                d) DISPLAY_MODE=day;    read_status; draw_ui "$LAST_STATE" "$LAST_CHECKED"; i=$seconds ;;
                l) if (( EMAIL_ENABLED )); then
                       "$DAEMON" --send-log &
                       draw_ui "$last_state" "$last_checked"
                       i=$seconds
                   fi ;;
            esac
        fi
    done
    printf '%72s\r' ''
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "${1:-}" in
    --help|-h)
        cat <<'EOF'
Usage: network-watch.sh [--help]

  (no args)   Start the live terminal UI (starts the daemon automatically)
  --help      Show this message

The daemon (network-watchd) runs checks every 30s in the background.
Keys: [m] minute  [h] hour  [d] day  [l] send log by email
EOF
        ;;
    *)
        DAEMON_PID=""
        trap 'stop_daemon; exit' INT TERM EXIT
        start_daemon_if_needed

        # Wait up to 5s for first status file if daemon is freshly started
        waited=0
        while [[ ! -f "$STATUS_FILE" && $waited -lt 5 ]]; do
            sleep 1; (( waited++ )) || true
        done

        LAST_STATE="OK" LAST_CHECKED=""
        read_status

        while true; do
            draw_ui "$LAST_STATE" "$LAST_CHECKED"
            run_countdown 30 "$LAST_STATE" "$LAST_CHECKED"
            read_status
        done
        ;;
esac
