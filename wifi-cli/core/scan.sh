#!/bin/bash

# Parses networks-01.csv into BSSID,channel,ESSID,dBm lines.
# Groups by ESSID — when multiple APs share the same name, only the strongest
# signal (highest/least-negative dBm) is kept so the attack targets the AP
# your card hears best. Hidden networks (empty ESSID) are kept separate by BSSID.
# Output is sorted by signal strength (strongest first).
_parse_networks() {
    awk -F',' '
    NR>2 && $1 ~ /:/ {
        gsub(/^ +| +$/, "", $1)
        gsub(/^ +| +$/, "", $4)
        gsub(/^ +| +$/, "", $9)
        gsub(/^ +| +$/, "", $14)
        gsub(/[^0-9].*/, "", $4)

        bssid   = $1
        channel = $4
        power   = $9 + 0
        essid   = $14
        display = (essid != "") ? essid : "<hidden>"

        # Hidden networks: key by BSSID so they stay separate
        key = (essid != "") ? essid : bssid

        if (!(key in best_power) || power > best_power[key]) {
            best_power[key]   = power
            best_bssid[key]   = bssid
            best_channel[key] = channel
            best_display[key] = display
        }
    }
    END {
        for (key in best_bssid)
            printf "%s,%s,%s,%s\n", best_bssid[key], best_channel[key], best_display[key], best_power[key]
    }' networks-01.csv | sort -t',' -k4 -rn
}

# Display networks with signal strength bars
_display_networks() {
    local data="$1"
    local i=1
    while IFS=',' read -r bssid channel essid dbm; do
        # Color code by signal strength
        local sig_color
        if (( dbm >= -50 )); then
            sig_color="$BOLD_GREEN"
        elif (( dbm >= -70 )); then
            sig_color="$BOLD_YELLOW"
        else
            sig_color="$BOLD_RED"
        fi
        printf "  ${BOLD_CYAN}%2d)${NC} %-28s ${DIM}ch %-3s${NC} ${sig_color}%4s dBm${NC}\n" \
            "$i" "$essid" "$channel" "$dbm"
        (( i++ ))
    done <<< "$data"
}

scan_networks() {

if [[ -z "$mon_iface" ]]; then
echo -e "${BOLD_RED}[!]${NC} Monitor mode not enabled!"
pause
return
fi

clear
echo -e "${BOLD_CYAN}Scan duration:${NC}"
echo -e "  ${BOLD_CYAN}[1]${NC} Quick   ${DIM}(10s)${NC}"
echo -e "  ${BOLD_CYAN}[2]${NC} Normal  ${DIM}(20s)${NC}"
echo -e "  ${BOLD_CYAN}[3]${NC} Thorough ${DIM}(45s)${NC}"
echo
read -p "  Choice [default: 2]: " dur_choice
case "$dur_choice" in
    1) scan_duration=10 ;;
    3) scan_duration=45 ;;
    *) scan_duration=20 ;;
esac

echo
echo -e "${BOLD_CYAN}[+]${NC} Starting network scan on ${BOLD_GREEN}${mon_iface}${NC}..."
echo

rm -f networks-01.csv 2>/dev/null

airodump-ng "$mon_iface" -w networks --output-format csv &>/dev/null &
scan_pid=$!

sleep "$scan_duration" &
spinner $! "$(scan_flavor) (${scan_duration}s)"

kill $scan_pid 2>/dev/null
wait $scan_pid 2>/dev/null
scan_pid=""

if [[ ! -f networks-01.csv ]]; then
echo
echo -e "${BOLD_RED}[!]${NC} Scan failed. No output file created."
pause
return
fi

results=$(_parse_networks)

if [[ -z "$results" ]]; then
echo
echo -e "${BOLD_YELLOW}[!]${NC} Scan complete but no networks were found."
echo -e "    ${DIM}Check that monitor mode is active and you are near access points.${NC}"
pause
return
fi

echo
echo -e "${BOLD_CYAN}Available Networks:${NC}"
echo
_display_networks "$results"

pause
}

select_target() {

local results
results=$(_parse_networks)

if [[ -z "$results" ]]; then
echo -e "${BOLD_RED}[!]${NC} No scan data. Run a network scan first."
pause
return
fi

clear
echo -e "${BOLD_CYAN}Available Networks:${NC}"
echo
_display_networks "$results"
echo
read -p "  Select network number: " num

line=$(echo "$results" | sed -n "${num}p")

bssid=$(echo "$line"   | cut -d',' -f1)
channel=$(echo "$line" | cut -d',' -f2)
essid=$(echo "$line"   | cut -d',' -f3)

if [[ -z "$bssid" ]]; then
echo -e "${BOLD_RED}[!]${NC} Invalid selection"
pause
return
fi

echo
echo -e "${BOLD_CYAN}Selected Target:${NC}"
echo -e "  ${DIM}SSID    :${NC} ${BOLD_GREEN}${essid}${NC}"
echo -e "  ${DIM}BSSID   :${NC} ${BOLD_GREEN}${bssid}${NC}"
echo -e "  ${DIM}Channel :${NC} ${BOLD_GREEN}${channel}${NC}"

pause
}
