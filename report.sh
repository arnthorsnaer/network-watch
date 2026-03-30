#!/usr/bin/env bash
# report.sh — network health heatmap
# Usage: ./report.sh [minute|hour|day]   (default: hour)
#
# minute — rolling 60-minute window, one column per minute
# hour   — rolling 24-hour window,   one column per hour
# day    — rolling 30-day window,    one column per day

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/NetworkWatch"
DATA_FILE="$APP_SUPPORT/checks.csv"
LAST_EMAIL_FILE="$APP_SUPPORT/last-email.txt"
MODE="${1:-hour}"

# Load .env for email status (optional, don't fail if missing)
source "$SCRIPT_DIR/.env" 2>/dev/null || true

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

LABEL_WIDTH=9
CHECK_NAMES=("Overall" "WiFi" "Router" "Internet" "DNS" "Web")

# Cell width — set per mode in render(); read by cell()
CELL_WIDTH=2

# ── Colors ────────────────────────────────────────────────────────────────────
# Smooth gradient: 0%=red → 50%=yellow → 100%=green. -1=no data (grey).

cell_bg() {
    local rate=$1
    local r g b t
    if (( rate < 0 )); then
        printf '\033[48;2;48;54;61m'; return
    fi
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

cell() {
    local rate=$1
    cell_bg "$rate"; printf '%*s' "${CELL_WIDTH}" ''; printf "$RESET"
}

# ── Aggregation ───────────────────────────────────────────────────────────────
# Outputs 5 lines of comma-separated success-rate integers, then "---", then incident count.

aggregate() {
    local window_start=$1 window_end=$2 bucket_size=$3 num_buckets=$4

    awk -v ws="$window_start" -v we="$window_end" \
        -v bsize="$bucket_size" -v nb="$num_buckets" \
    'BEGIN { FS="," }
    /^[0-9]/ {
        epoch = $1 + 0
        if (epoch < ws || epoch >= we) next
        bucket = int((epoch - ws) / bsize)
        if (bucket < 0 || bucket >= nb) next
        for (c = 1; c <= 5; c++) {
            k = bucket "_" c
            total[k]++
            if ($(c+1) + 0 == 1) success[k]++
        }
        all_ok = ($2+0==1 && $3+0==1 && $4+0==1 && $5+0==1 && $6+0==1)
        bk = "b_" bucket
        bucket_total[bk]++
        if (all_ok) bucket_ok[bk]++
    }
    END {
        # Row 1: Overall
        for (b = 0; b < nb; b++) {
            bk = "b_" b
            if (bk in bucket_total)
                printf "%d", int(bucket_ok[bk] * 100 / bucket_total[bk])
            else
                printf "-1"
            printf (b < nb-1) ? "," : "\n"
        }
        # Rows 2-6: individual checks
        for (c = 1; c <= 5; c++) {
            for (b = 0; b < nb; b++) {
                k = b "_" c
                if (k in total)
                    printf "%d", int(success[k] * 100 / total[k])
                else
                    printf "-1"
                printf (b < nb-1) ? "," : "\n"
            }
        }
        print "---"
        incidents = 0
        for (b = 0; b < nb; b++) {
            bk = "b_" b
            if (bk in bucket_total && bucket_ok[bk] * 100 / bucket_total[bk] < 80)
                incidents++
        }
        print incidents
    }' "$DATA_FILE" 2>/dev/null
}

# ── Rendering ─────────────────────────────────────────────────────────────────

render() {
    local num_buckets=$1 bucket_size=$2 window_start=$3 window_end=$4
    local title=$5 label_every=$6
    CELL_WIDTH=${7:-2}

    # Aggregate
    local raw_output
    raw_output=$(aggregate "$window_start" "$window_end" "$bucket_size" "$num_buckets")

    local rows=() incidents=0 in_section2=0
    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            in_section2=1
        elif (( in_section2 )); then
            incidents=$line
        else
            rows+=("$line")
        fi
    done <<< "$raw_output"

    # Pad missing rows
    local no_data_row="-1"
    for _ in $(seq 2 $num_buckets); do no_data_row="$no_data_row,-1"; done
    while (( ${#rows[@]} < 6 )); do rows+=("$no_data_row"); done

    # ── Print ─────────────────────────────────────────────────────────────────
    echo
    printf "  ${BOLD}%s${RESET}\n" "$title"
    echo

    # Incident counter
    if (( incidents == 0 )); then
        printf "  No incidents in this window.\n"
    elif (( incidents == 1 )); then
        printf "  ${BOLD}1 incident${RESET} in this window.\n"
    else
        printf "  ${BOLD}%d incidents${RESET} in this window.\n" "$incidents"
    fi

    # Email status
    if [[ -n "${ALERT_EMAIL:-}" ]]; then
        local last_sent="never"
        if [[ -f "$LAST_EMAIL_FILE" ]]; then
            local raw_ts today
            raw_ts=$(cat "$LAST_EMAIL_FILE")
            today=$(date '+%Y-%m-%d')
            if [[ "$raw_ts" == "$today"* ]]; then
                last_sent="today at ${raw_ts#* }"
            else
                last_sent="$raw_ts"
            fi
        fi
        printf "  Email: ${BOLD}${ALERT_EMAIL}${RESET} — last sent: %s\n" "$last_sent"
    else
        printf "  ${DIM}Email alerts: not configured${RESET}\n"
    fi
    echo

    # Column header
    printf '%*s ' $LABEL_WIDTH ''
    if [[ "$MODE" == "minute" ]]; then
        # Build 60-char string with HH:MM labels at positions 0, 15, 30, 45
        local hdr; hdr=$(printf '%*s' $num_buckets '')
        for pos in 0 15 30 45; do
            local lbl; lbl=$(date -r $(( window_start + pos * bucket_size )) '+%H:%M')
            hdr="${hdr:0:$pos}${lbl}${hdr:$(( pos + 5 ))}"
        done
        printf '%s\n' "$hdr"
    else
        # Per-bucket labels (2-char each)
        for (( b=0; b<num_buckets; b++ )); do
            if (( b % label_every == 0 )); then
                local lbl_ep=$(( window_start + b * bucket_size ))
                if [[ "$MODE" == "hour" ]]; then
                    printf '%s' "$(date -r $lbl_ep '+%H')"
                else
                    printf '%s' "$(date -r $lbl_ep '+%d')"
                fi
            else
                printf '%*s' $CELL_WIDTH ''
            fi
        done
        echo
    fi

    # Data rows
    local data_width=$(( num_buckets * CELL_WIDTH ))
    for (( c=0; c<6; c++ )); do
        printf "${BOLD}%-*s${RESET} " $LABEL_WIDTH "${CHECK_NAMES[$c]}"
        local old_ifs="$IFS"; IFS=',' read -ra rates <<< "${rows[$c]}"; IFS="$old_ifs"
        for rate in "${rates[@]}"; do cell "$rate"; done
        echo
        # Separator after Overall row
        if (( c == 0 )); then
            printf '%*s ' $LABEL_WIDTH ''; printf '·%.0s' $(seq 1 $data_width); echo
        fi
    done

    # Axis
    printf '%*s ' $LABEL_WIDTH ''
    printf '←'; printf '─%.0s' $(seq 1 $(( data_width - 2 ))); printf '→'; echo

    local left_label right_label="now"
    case "$MODE" in
        minute) left_label="60m ago" ;;
        hour)   left_label="24h ago" ;;
        day)    left_label="30d ago" ;;
    esac
    printf '%*s ' $LABEL_WIDTH ''
    printf "%-*s%s\n" $(( data_width - ${#right_label} )) "$left_label" "$right_label"

    # Legend
    echo
    printf '  '
    cell 100; printf ' ok  '
    cell 75;  printf ' 75%%  '
    cell 50;  printf ' 50%%  '
    cell 25;  printf ' 25%%  '
    cell 0;   printf ' down  '
    cell -1;  printf ' no data'
    echo; echo
}

# ── Entry point ───────────────────────────────────────────────────────────────

if [[ ! -f "$DATA_FILE" ]]; then
    echo
    echo "No data yet — start network-watch.sh first."
    echo
    exit 0
fi

now=$(date +%s)

case "$MODE" in
    minute)
        render 60 60 $(( now - 3600 )) $now "Network Health — Last 60 Minutes" 15 1
        ;;
    hour)
        render 24 3600 $(( now - 86400 )) $now "Network Health — Last 24 Hours" 4 2
        ;;
    day)
        render 30 86400 $(( now - 2592000 )) $now "Network Health — Last 30 Days" 7 2
        ;;
    *)
        echo "Usage: $0 [minute|hour|day]"
        exit 1
        ;;
esac
