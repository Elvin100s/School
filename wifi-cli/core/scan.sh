#!/bin/bash

# Shared awk block: parses networks-01.csv into BSSID,channel,ESSID lines
_parse_networks() {
    awk -F',' '
    NR>2 && $1 ~ /:/ {
        gsub(/^ +| +$/, "", $1)
        gsub(/^ +| +$/, "", $4)
        gsub(/^ +| +$/, "", $14)
        if (!seen[$1]++) {
            printf "%s,%s,%s\n", $1,$4,$14
        }
    }' networks-01.csv
}

scan_networks() {

if [[ -z "$mon_iface" ]]; then
echo "Monitor mode not enabled!"
pause
return
fi

clear
echo -e "${BOLD_CYAN}[+]${NC} Starting network scan on ${BOLD_GREEN}${mon_iface}${NC}..."
echo

rm -f networks-01.csv 2>/dev/null

airodump-ng "$mon_iface" -w networks --output-format csv &>/dev/null &
scan_pid=$!

sleep 10 &
spinner $! "Scanning for networks (10s)"

kill $scan_pid 2>/dev/null
wait $scan_pid 2>/dev/null
scan_pid=""

if [[ ! -f networks-01.csv ]]; then
echo
echo "Scan failed. No output file created."
pause
return
fi

results=$(_parse_networks)

if [[ -z "$results" ]]; then
echo
echo "Scan complete but no networks were found."
echo "Check that monitor mode is active and you are near access points."
pause
return
fi

echo
echo "Available Networks:"
echo

echo "$results" | nl

pause
}

select_target() {

echo
read -p "Select network number: " num

line=$(_parse_networks | sed -n "${num}p")

bssid=$(echo "$line" | cut -d',' -f1)
channel=$(echo "$line" | cut -d',' -f2)
essid=$(echo "$line" | cut -d',' -f3)

if [[ -z "$bssid" ]]; then
echo "Invalid selection"
pause
return
fi

echo
echo "Selected Target:"
echo "SSID    : $essid"
echo "BSSID   : $bssid"
echo "Channel : $channel"

pause
}
