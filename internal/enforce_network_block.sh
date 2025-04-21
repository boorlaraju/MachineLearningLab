#!/bin/bash

# Requires: sudo
# Run: sudo ./enforce_network_block.sh

START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/network_block_log.txt"
STATUS_INTERVAL_MINUTES=10
CHECK_INTERVAL_SECONDS=10

echo "====== NETWORK BLOCK SESSION ======" >> "$LOG_FILE"
echo "Start: $START_TIME" >> "$LOG_FILE"
echo "Log File: $LOG_FILE" >> "$LOG_FILE"
echo "===================================" >> "$LOG_FILE"
echo "Started at $START_TIME"
echo "Tracking user applications, disabling Wi-Fi, Bluetooth, and Ethernet..."

declare -A known_pids

log_status() {
    local now=$(date '+%Y-%m-%d %H:%M:%S')
    local elapsed=$(( ($(date +%s) - $(date -d "$START_TIME" +%s)) / 60 ))
    local wifi_status=$(nmcli radio wifi)
    local bt_status=$(rfkill list bluetooth | grep -i "Soft blocked" | awk '{print $3}')

    echo "[$now] Running for $elapsed min | Wi-Fi: $wifi_status | Bluetooth: $bt_status" | tee -a "$LOG_FILE"
}

log_app_launch() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local app="$1"
    echo "[$timestamp] Application Started: $app" | tee -a "$LOG_FILE"
}

cleanup() {
    echo -e "\nStopped at: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "===================================" >> "$LOG_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

last_status_time=$(date +%s)

while true; do
    # Disable Wi-Fi, Bluetooth, and Ethernet
    nmcli radio wifi off
    rfkill block bluetooth
    ethernet_interfaces=$(nmcli -t -f DEVICE,TYPE d | grep ethernet | cut -d: -f1)
    for eth in $ethernet_interfaces; do
        nmcli device disconnect "$eth"
    done

    # Log every 10 minutes
    now_sec=$(date +%s)
    if (( now_sec - last_status_time >= STATUS_INTERVAL_MINUTES * 60 )); then
        log_status
        last_status_time=$now_sec
    fi

    # Detect new user-facing apps
    while read -r pid app; do
        if [[ -z "${known_pids[$pid]}" ]]; then
            known_pids[$pid]=1
            log_app_launch "$app (PID: $pid)"
        fi
    done < <(wmctrl -lp | awk '{print $3}' | while read pid; do
        cmd=$(ps -p $pid -o comm= 2>/dev/null)
        [[ -n "$cmd" ]] && echo "$pid $cmd"
    done)

    sleep $CHECK_INTERVAL_SECONDS
done

