#!/bin/bash

scan_clients() {

if [[ -z "$mon_iface" || -z "$bssid" || -z "$channel" ]]; then
echo "Set interface, target, and channel first!"
pause
return
fi

if ! [[ "$channel" =~ ^[0-9]+$ ]] || (( channel < 1 || channel > 165 )); then
echo "Invalid channel: '$channel'. Must be a number between 1 and 165."
pause
return
fi

clear
echo -e "${BOLD_CYAN}[+]${NC} Scanning clients on ${BOLD_GREEN}${bssid}${NC} (channel ${BOLD_GREEN}${channel}${NC})..."
echo

rm -f scan-01.csv 2>/dev/null

airodump-ng -c "$channel" --bssid "$bssid" -w scan "$mon_iface" &>/dev/null &
scan_pid=$!

sleep 8 &
spinner $! "Listening for clients (8s)"

kill $scan_pid 2>/dev/null
wait $scan_pid 2>/dev/null
scan_pid=""

if [[ ! -f scan-01.csv ]]; then
echo "Scan failed. No output file found."
pause
return
fi

# Client section starts after the blank line that follows the AP section
clients=$(awk '
/^$/ { found=1; next }
found && /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
    gsub(/^ +| +$/, "", $1)
    print $1
}
' scan-01.csv | sort -u)

echo
echo "Clients Found:"
echo

if [[ -z "$clients" ]]; then
    echo "No clients detected."
else
    echo "$clients" | nl
fi

pause
}
