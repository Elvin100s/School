#!/bin/bash

# Look up ESSID for a BSSID directly from the raw CSV so any AP is found,
# not just the strongest one chosen by _parse_networks.
_lookup_essid() {
    local target_bssid="$1"
    local result=""
    if [[ -f networks-01.csv ]]; then
        result=$(awk -F',' -v b="$target_bssid" '
        NR>2 && $1 ~ /:/ {
            gsub(/^ +| +$/, "", $1)
            gsub(/^ +| +$/, "", $14)
            if (tolower($1) == tolower(b)) {
                print ($14 != "" ? $14 : "<hidden>")
                exit
            }
        }' networks-01.csv)
    fi
    echo "${result:-Unknown}"
}

# Display clients grouped by their associated BSSID
# Input: newline-separated "MAC BSSID" lines
_display_clients_grouped() {
    local data="$1"
    local counter=1
    local prev_bssid=""

    while IFS=' ' read -r mac assoc_bssid; do
        if [[ "$assoc_bssid" != "$prev_bssid" ]]; then
            local essid
            essid=$(_lookup_essid "$assoc_bssid")
            echo
            echo -e "  ${BOLD_CYAN}Network: ${BOLD_GREEN}${essid}${NC} ${DIM}(${assoc_bssid})${NC}"
        fi
        echo -e "    ${BOLD_YELLOW}${counter})${NC} ${mac}"
        prev_bssid="$assoc_bssid"
        (( counter++ ))
    done <<< "$data"
}

scan_clients() {

if [[ -z "$mon_iface" || -z "$channel" ]]; then
echo -e "${BOLD_RED}[!]${NC} Set interface and enable monitor mode first!"
pause
return
fi

if ! [[ "$channel" =~ ^[0-9]+$ ]] || (( channel < 1 || channel > 165 )); then
echo -e "${BOLD_RED}[!]${NC} Invalid channel: '${BOLD_YELLOW}${channel}${NC}'. Must be a number between 1 and 165."
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
echo -e "${BOLD_CYAN}[+]${NC} Scanning all clients on channel ${BOLD_GREEN}${channel}${NC}..."
echo

rm -f scan-01.csv 2>/dev/null

# No --bssid filter — capture all clients on this channel
airodump-ng -c "$channel" -w scan "$mon_iface" &>/dev/null &
scan_pid=$!

sleep "$scan_duration" &
spinner $! "$(scan_flavor) (${scan_duration}s)"

kill $scan_pid 2>/dev/null
wait $scan_pid 2>/dev/null
scan_pid=""

if [[ ! -f scan-01.csv ]]; then
echo -e "${BOLD_RED}[!]${NC} Scan failed. No output file found."
pause
return
fi

# CSV client section: Station MAC = col1, associated BSSID = col6
# A blank line separates the AP section from the client section
# Filter out unassociated clients (BSSID = "(not associated)" or 00:00:00:00:00:00)
# Output: "CLIENT_MAC ASSOC_BSSID" sorted by BSSID then MAC
clients=$(awk -F',' '
/^[[:space:]]*$/ { found=1; next }
found {
    mac=$1; bssid=$6
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", mac)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", bssid)
    if (mac  ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ &&
        bssid ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ &&
        bssid != "00:00:00:00:00:00") {
        print mac, bssid
    }
}' scan-01.csv | sort -t' ' -k2,2 -k1,1 | awk '!seen[$0]++')

echo
echo -e "${BOLD_CYAN}Clients Found:${NC}"

if [[ -z "$clients" ]]; then
    echo
    echo -e "${BOLD_YELLOW}[!]${NC} No associated clients detected."
    echo -e "    ${DIM}Only probing (unconnected) devices were seen, or the channel is quiet.${NC}"
else
    target_acquired
    _display_clients_grouped "$clients"
fi

echo
pause
}
