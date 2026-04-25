#!/bin/bash

# Parses networks-01.csv into BSSID,channel,ESSID,dBm,band lines.
# Deduplicates per ESSID+band pair — the same network name on 2.4G and 5G
# produces two separate entries so you can target either band precisely.
# Within each band, only the strongest-signal AP is kept.
# Hidden networks (empty ESSID) are kept separate by BSSID.
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

        # Determine band from channel number
        band = (channel + 0 >= 36) ? "5G" : "2.4G"

        # Dedup key: essid+band for named APs, BSSID for hidden (stay unique)
        key = (essid != "") ? essid "\t" band : bssid

        if (!(key in best_power) || power > best_power[key]) {
            best_power[key]   = power
            best_bssid[key]   = bssid
            best_channel[key] = channel
            best_display[key] = display
            best_band[key]    = band
        }
    }
    END {
        for (key in best_bssid)
            printf "%s,%s,%s,%s,%s\n", best_bssid[key], best_channel[key], best_display[key], best_power[key], best_band[key]
    }' networks-01.csv | sort -t',' -k4 -rn
}

# Display networks with signal strength bars and band labels
_display_networks() {
    local data="$1"
    local i=1
    while IFS=',' read -r bssid channel essid dbm band; do
        # Signal strength color
        local sig_color
        if (( dbm >= -50 )); then
            sig_color="$BOLD_GREEN"
        elif (( dbm >= -70 )); then
            sig_color="$BOLD_YELLOW"
        else
            sig_color="$BOLD_RED"
        fi

        # Band label color: yellow for 2.4G, blue for 5G
        local band_str band_color
        if [[ "$band" == "5G" ]]; then
            band_color="$BOLD_BLUE"
            band_str="5G"
        else
            band_color="$BLUE"
            band_str="2.4G"
        fi

        printf "  ${BOLD_CYAN}%2d)${NC} %-28s ${DIM}ch %-4s${NC} ${band_color}%-4s${NC} ${sig_color}%4s dBm${NC}\n" \
            "$i" "$essid" "$channel" "$band_str" "$dbm"
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
echo -e "  ${BOLD_CYAN}[1]${NC} Quick    ${DIM}(10s)${NC}"
echo -e "  ${BOLD_CYAN}[2]${NC} Normal   ${DIM}(20s)${NC}"
echo -e "  ${BOLD_CYAN}[3]${NC} Thorough ${DIM}(45s)${NC}"
echo
read -p "  Choice [default: 2]: " dur_choice
case "$dur_choice" in
    1) scan_duration=10 ;;
    3) scan_duration=45 ;;
    *) scan_duration=20 ;;
esac

# Detect 5 GHz hardware capability for this adapter
local _supports_5g=false
local _phy_idx
_phy_idx=$(iw dev "$mon_iface" info 2>/dev/null | awk '/wiphy/{print $2}')
if [[ -n "$_phy_idx" ]] && \
   iw phy "phy${_phy_idx}" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
    _supports_5g=true
fi

# Band picker — only show 5G options if hardware supports it
echo
echo -e "${BOLD_CYAN}Frequency band:${NC}"
echo -e "  ${BOLD_CYAN}[1]${NC} 2.4 GHz ${DIM}(channels 1-14)${NC}"
if $_supports_5g; then
    echo -e "  ${BOLD_CYAN}[2]${NC} 5 GHz   ${DIM}(channels 36-165)${NC}"
    echo -e "  ${BOLD_CYAN}[3]${NC} Both    ${DIM}(slower — full spectrum sweep)${NC}"
else
    echo -e "  ${DIM}  5 GHz options unavailable — adapter is 2.4 GHz only${NC}"
fi
echo
read -p "  Choice [default: 1]: " band_choice

local _band_flag="" _band_label="2.4 GHz"
if $_supports_5g; then
    case "$band_choice" in
        2) _band_flag="--band a";   _band_label="5 GHz" ;;
        3) _band_flag="--band abg"; _band_label="2.4 + 5 GHz" ;;
        *) _band_flag="";           _band_label="2.4 GHz" ;;
    esac
fi

echo
echo -e "${BOLD_CYAN}[+]${NC} Starting network scan on ${BOLD_GREEN}${mon_iface}${NC} ${DIM}(${_band_label})${NC}..."
echo

rm -f networks-01.csv 2>/dev/null

# shellcheck disable=SC2086
airodump-ng $_band_flag "$mon_iface" -w networks --output-format csv &>/dev/null &
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
echo -e "  ${DIM}BSSID   :${NC} ${BOLD_MAGENTA}${bssid}${NC}"
echo -e "  ${DIM}Channel :${NC} ${BOLD_GREEN}${channel}${NC}"

pause
}
