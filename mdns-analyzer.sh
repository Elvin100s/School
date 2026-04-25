#!/usr/bin/env bash
# mdns-analyzer.sh — Educational mDNS/Bonjour service discovery analyzer
# Passively listens for mDNS announcements, fingerprints devices by service type,
# and displays results in a structured table.
# For cybersecurity coursework — use only on networks you own or have permission to analyze.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
CAPTURE_DURATION=30
INTERFACE=""
AVAHI_OUT="/tmp/mdns_avahi_$$.txt"
PCAP_FILE="/tmp/mdns_cap_$$.pcap"
VERBOSE=false
BACKEND=""   # auto-detected: "avahi" or "tcpdump"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
MAG='\033[0;35m'
CYN='\033[0;36m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'
BOLD='\033[1m'

# ─── Service type → Device fingerprint ────────────────────────────────────────
# Format: "service_type|Friendly Label|Category"
# Checked in order — first match wins for device type classification.
declare -a SERVICE_PATTERNS=(
    # Apple — iOS / iPadOS
    "_apple-mobdev2._tcp|iOS Device|Apple"
    "_apple-mobdev._tcp|iOS Device|Apple"
    "_companion-link._tcp|Apple Watch|Apple"
    # Apple — HomeKit
    "_homekit._tcp|HomeKit Hub|Apple"
    "_hap._tcp|HomeKit Accessory|Apple"
    # Apple — AirPlay / Audio
    "_airplay._tcp|AirPlay Receiver|Apple"
    "_raop._tcp|AirPlay Audio|Apple"
    "_ippusb._tcp|AirPrint Printer|Apple"
    # Apple — macOS sharing
    "_daap._tcp|iTunes/Music Share|macOS"
    "_dacp._tcp|Apple Remote|macOS"
    "_adisk._tcp|Time Machine|macOS"
    "_afpovertcp._tcp|AFP File Share|macOS"
    "_eppc._tcp|Remote Apple Events|macOS"
    "_rdlink._tcp|Continuity Link|macOS"
    "_sleep-proxy._udp|Bonjour Sleep Proxy|macOS"
    # Google / Chromecast
    "_googlecast._tcp|Google Cast Device|Google"
    "_privet._tcp|Google Cloud Print|Google"
    "_googlerpc._tcp|Google Service|Google"
    # Android TV
    "_androidtvremote2._tcp|Android TV|Android"
    "_androidtvremote._tcp|Android TV|Android"
    # Windows
    "_smb._tcp|SMB File Share|Windows"
    "_microsoft-ds._tcp|Windows Share|Windows"
    # Printers / Scanners
    "_ipp._tcp|Network Printer|Printer"
    "_ipps._tcp|Network Printer|Printer"
    "_pdl-datastream._tcp|PDL Printer|Printer"
    "_printer._tcp|Network Printer|Printer"
    "_scanner._tcp|Network Scanner|Printer"
    "_uscan._tcp|USB Network Scanner|Printer"
    # Media Servers / Players
    "_spotify-connect._tcp|Spotify Connect|Media"
    "_sonos._tcp|Sonos Speaker|Media"
    "_soundtouch._tcp|Bose SoundTouch|Media"
    "_squeezebox._tcp|Logitech Media|Media"
    "_plex._tcp|Plex Media Server|Media"
    "_plexmediasvr._tcp|Plex Media Server|Media"
    "_xbmc._tcp|Kodi / XBMC|Media"
    "_kodi._tcp|Kodi|Media"
    # Gaming
    "_nvstream._tcp|NVIDIA Shield|Gaming"
    # Smart Home / IoT
    "_homeassistant._tcp|Home Assistant|IoT"
    "_hue._tcp|Philips Hue|IoT"
    "_miio._udp|Xiaomi Device|IoT"
    "_mqtt._tcp|MQTT Broker|IoT"
    "_coap._udp|CoAP Device|IoT"
    # Linux / Network services
    "_workstation._tcp|Linux Workstation|Linux"
    "_ssh._tcp|SSH Server|Linux/Mac"
    "_sftp-ssh._tcp|SFTP Server|Linux/Mac"
    "_http._tcp|HTTP Web Service|Server"
    "_https._tcp|HTTPS Web Service|Server"
    "_ftp._tcp|FTP Server|Server"
    "_telnet._tcp|Telnet Service|IoT"
)

# ─── Hostname hint patterns ────────────────────────────────────────────────────
# Secondary signal — used to refine or supply device type when services are generic.
# Format: "substring_pattern|Friendly Device Name|OS"
declare -a HOSTNAME_PATTERNS=(
    "-iPhone|iPhone|iOS"
    "-iPad|iPad|iPadOS"
    "-iPod|iPod touch|iOS"
    "MacBook|MacBook|macOS"
    "iMac|iMac|macOS"
    "Mac-mini|Mac mini|macOS"
    "Mac-Pro|Mac Pro|macOS"
    "MacPro|Mac Pro|macOS"
    "DESKTOP-|Windows Desktop|Windows"
    "-PC|Windows PC|Windows"
    "raspberrypi|Raspberry Pi|Linux"
    "Galaxy|Samsung Android|Android"
    "Pixel|Google Pixel|Android"
    "android|Android Device|Android"
    "synology|Synology NAS|NAS"
    "qnap|QNAP NAS|NAS"
    "ubuntu|Ubuntu Linux|Linux"
    "debian|Debian Linux|Linux"
)

# ─── Category → display color ─────────────────────────────────────────────────
category_color() {
    case "$1" in
        Apple)     echo "$MAG" ;;
        macOS)     echo "$MAG" ;;
        Google)    echo "$GRN" ;;
        Android)   echo "$GRN" ;;
        Windows)   echo "$BLU" ;;
        Printer)   echo "$CYN" ;;
        Media)     echo "$YLW" ;;
        Gaming)    echo "$YLW" ;;
        IoT)       echo "$RED" ;;
        Linux)     echo "$CYN" ;;
        "Linux/Mac") echo "$CYN" ;;
        NAS)       echo "$WHT" ;;
        Server)    echo "$WHT" ;;
        *)         echo "$DIM" ;;
    esac
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}mdns-analyzer.sh${RST} — Educational mDNS/Bonjour Discovery Analyzer

${BOLD}Usage:${RST}
  sudo $0 [OPTIONS]

${BOLD}Options:${RST}
  -i <iface>     Network interface (required for tcpdump mode; optional for avahi)
  -d <seconds>   Listen duration in seconds (default: ${CAPTURE_DURATION})
  -b <backend>   Force backend: 'avahi' or 'tcpdump'
  -v             Verbose: list every captured service entry before the summary
  -h             Show this help

${BOLD}Backends:${RST}
  avahi    Uses avahi-browse — richest data, resolves hostnames and IPs natively.
           Install: sudo apt install avahi-daemon avahi-utils
  tcpdump  Raw pcap capture on UDP 5353 — fallback when avahi is unavailable.
           Install: sudo apt install tcpdump

${BOLD}Examples:${RST}
  sudo $0
  sudo $0 -d 60
  sudo $0 -i wlan0 -b tcpdump
  sudo $0 -v

${BOLD}Notes:${RST}
  - Passively listens only — no packets are injected
  - Device identification is heuristic, based on advertised service types
  - For use on networks you own or have explicit permission to analyze
EOF
    exit 0
}

# ─── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
    # Determine backend
    if [[ -n "$BACKEND" ]]; then
        case "$BACKEND" in
            avahi)
                command -v avahi-browse &>/dev/null || {
                    echo -e "${RED}[!] avahi-browse not found. Install: sudo apt install avahi-utils${RST}"
                    exit 1
                }
                ;;
            tcpdump)
                command -v tcpdump &>/dev/null || {
                    echo -e "${RED}[!] tcpdump not found. Install: sudo apt install tcpdump${RST}"
                    exit 1
                }
                ;;
            *)
                echo -e "${RED}[!] Unknown backend '${BACKEND}'. Use 'avahi' or 'tcpdump'.${RST}"
                exit 1
                ;;
        esac
    else
        # Auto-detect
        if command -v avahi-browse &>/dev/null; then
            BACKEND="avahi"
        elif command -v tcpdump &>/dev/null; then
            BACKEND="tcpdump"
        else
            echo -e "${RED}[!] No supported backend found.${RST}"
            echo -e "${DIM}    Install avahi-utils: sudo apt install avahi-daemon avahi-utils${RST}"
            echo -e "${DIM}    Or tcpdump:          sudo apt install tcpdump${RST}"
            exit 1
        fi
    fi

    # avahi backend: warn if daemon is not running
    if [[ "$BACKEND" == "avahi" ]]; then
        if ! pgrep -x avahi-daemon > /dev/null 2>&1; then
            echo -e "${YLW}[!] avahi-daemon does not appear to be running.${RST}"
            echo -e "${DIM}    Start it: sudo systemctl start avahi-daemon${RST}"
            echo -e "${DIM}    Continuing — results may be empty if it stays down.${RST}"
        fi
    fi

    # tcpdump needs root and an interface
    if [[ "$BACKEND" == "tcpdump" ]]; then
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}[!] tcpdump mode requires root. Run with sudo.${RST}"
            exit 1
        fi
        if [[ -z "$INTERFACE" ]]; then
            INTERFACE=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
            if [[ -z "$INTERFACE" ]]; then
                echo -e "${RED}[!] Could not determine default interface. Specify with -i.${RST}"
                list_interfaces
                exit 1
            fi
            echo -e "${DIM}[*] Auto-selected interface: ${INTERFACE}${RST}"
        fi
        if ! ip link show "$INTERFACE" &>/dev/null; then
            echo -e "${RED}[!] Interface '${INTERFACE}' not found.${RST}"
            list_interfaces
            exit 1
        fi
    fi
}

# ─── Interface listing ────────────────────────────────────────────────────────
list_interfaces() {
    echo -e "${CYN}Available interfaces:${RST}"
    ip -o link show 2>/dev/null \
        | awk -F': ' '{print "  " $2}' \
        | grep -v '^ *lo$'
}

# ─── ARP table ────────────────────────────────────────────────────────────────
declare -A ARP_TABLE

build_arp_table() {
    while IFS= read -r line; do
        local ip mac
        ip=$(echo "$line"  | grep -oP '\(\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?=\))')
        mac=$(echo "$line" | grep -oP '([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}')
        [[ -n "$ip" && -n "$mac" ]] && ARP_TABLE["$ip"]="${mac,,}"
    done < <(arp -n 2>/dev/null || true)
}

mac_for_ip() { echo "${ARP_TABLE[$1]:-<unknown>}"; }

# ─── Device type from service list ────────────────────────────────────────────
# $1 = space-separated list of service types, $2 = hostname
# Outputs "Friendly Label|Category"
infer_device() {
    local services="$1"
    local hostname="${2,,}"   # lowercase for pattern matching

    # Service-based (most authoritative)
    for entry in "${SERVICE_PATTERNS[@]}"; do
        local svcpat label cat
        IFS='|' read -r svcpat label cat <<< "$entry"
        if echo "$services" | grep -qF "$svcpat"; then
            echo "${label}|${cat}"
            return
        fi
    done

    # Hostname-based (fallback)
    for entry in "${HOSTNAME_PATTERNS[@]}"; do
        local pat label os
        IFS='|' read -r pat label os <<< "$entry"
        if echo "$hostname" | grep -qiF "$pat"; then
            echo "${label}|${os}"
            return
        fi
    done

    echo "Unknown Device|Unknown"
}

# ─── Shorten service type for display ─────────────────────────────────────────
# "_airplay._tcp" → "airplay"
short_svc() {
    echo "$1" | sed 's/^_//; s/\.\(tcp\|udp\)$//'
}

# ─── avahi-browse capture ─────────────────────────────────────────────────────
run_avahi() {
    local iface_flag=""
    [[ -n "$INTERFACE" ]] && iface_flag="--interface=$INTERFACE"

    echo -e "\n${BOLD}${CYN}[*] Listening via avahi-browse for ${CAPTURE_DURATION}s...${RST}"
    echo -e "${DIM}    Backend  : avahi-browse${RST}"
    [[ -n "$INTERFACE" ]] && echo -e "${DIM}    Interface: ${INTERFACE}${RST}"
    echo -e "${DIM}    Tip: Generate traffic (browse web, cast video) for richer results.${RST}\n"

    local spin='|/-\'
    local i=0 elapsed=0

    # Run avahi-browse in background, capture parseable output
    # -a = all service types, -r = resolve IPs/ports, -p = parseable, -k = no separator lines
    timeout "$CAPTURE_DURATION" avahi-browse -a -r -p \
        ${iface_flag:+"$iface_flag"} \
        > "$AVAHI_OUT" 2>/dev/null &
    local ab_pid=$!

    while kill -0 "$ab_pid" 2>/dev/null && [[ $elapsed -lt $CAPTURE_DURATION ]]; do
        printf "\r  ${YLW}Listening... [%s] %ds / %ds${RST}" \
            "${spin:$((i % 4)):1}" "$elapsed" "$CAPTURE_DURATION"
        sleep 1
        ((elapsed++)) || true
        ((i++))    || true
    done
    wait "$ab_pid" 2>/dev/null || true
    printf "\r${GRN}  [+] Capture complete (%ds).%s${RST}\n" "$elapsed" "          "
}

# Parse avahi-browse -p output.
# Parseable line format (semicolon-separated):
#   =[event];iface;proto;instance_name;service_type;domain;hostname;ip;port;txt
# We only use "=" (resolved) lines with valid IPs.
# Output per found entry: IP|HOSTNAME|SVC_TYPE|INSTANCE_NAME
parse_avahi() {
    local file="$1"
    [[ -s "$file" ]] || return

    grep '^=;' "$file" | while IFS=';' read -r _ev _if proto name svctype _dom host ip _port _txt; do
        # Skip IPv6 for now (avahi reports both)
        [[ "$proto" == "IPv6" ]] && continue
        # Skip entries without a real IP
        [[ -z "$ip" || "$ip" =~ ^fe80 || "$ip" =~ ^:: ]] && continue

        # Decode \032 (Avahi's space encoding) in instance name
        name=$(printf '%b' "${name//\\032/ }" 2>/dev/null || echo "$name")

        # Strip .local. suffix from hostname
        host="${host%.local.}"
        host="${host%.local}"

        printf '%s|%s|%s|%s\n' "$ip" "$host" "$svctype" "$name"
    done
}

# ─── tcpdump capture ──────────────────────────────────────────────────────────
run_tcpdump() {
    echo -e "\n${BOLD}${CYN}[*] Capturing mDNS on ${INTERFACE} for ${CAPTURE_DURATION}s...${RST}"
    echo -e "${DIM}    Backend  : tcpdump (UDP 5353)${RST}"
    echo -e "${DIM}    Tip: Generate traffic (browse web, cast video) for richer results.${RST}\n"

    local spin='|/-\'
    local i=0 elapsed=0

    tcpdump -i "$INTERFACE" -w "$PCAP_FILE" \
        --snapshot-length=0 \
        -G "$CAPTURE_DURATION" -W 1 \
        'udp port 5353' \
        2>/dev/null &
    local tc_pid=$!

    while kill -0 "$tc_pid" 2>/dev/null && [[ $elapsed -lt $CAPTURE_DURATION ]]; do
        printf "\r  ${YLW}Capturing... [%s] %ds / %ds${RST}" \
            "${spin:$((i % 4)):1}" "$elapsed" "$CAPTURE_DURATION"
        sleep 1
        ((elapsed++)) || true
        ((i++))    || true
    done
    wait "$tc_pid" 2>/dev/null || true
    printf "\r${GRN}  [+] Capture complete (%ds).%s${RST}\n" "$elapsed" "          "
}

# Parse tcpdump pcap for mDNS content.
# Uses: tcpdump -r pcap -n -v
#
# Patterns extracted:
#   Source IP     : "IP x.x.x.x.5353 >"
#   PTR record    : "PTR <name>._<svc>._tcp.local."    (service announcement)
#   A record      : "<hostname>.local. A x.x.x.x"       (hostname→IP binding)
#   SRV record    : "SRV <hostname>.local.:<port>"       (hostname for a service)
#
# Output: IP|HOSTNAME|SVC_TYPE|INSTANCE_NAME
parse_tcpdump() {
    [[ -s "$PCAP_FILE" ]] || return

    tcpdump -r "$PCAP_FILE" -n -v 2>/dev/null | awk '
    # Track current src IP from packet header lines (POSIX awk compatible)
    /IP [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.5353 >/ {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.5353$/) {
                tmp = $i; sub(/\.[^.]+$/, "", tmp); src = tmp; break
            }
        }
    }

    # PTR records — service instance announcements
    # target format: "InstanceName._svctype._(tcp|udp).local"
    /PTR [^ ]/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "PTR" && i < NF) {
                target = $(i+1)
                sub(/\.$/, "", target)
                # 2-arg match() is POSIX; extract svctype + instname via substr
                if (match(target, /_[-a-z0-9]+\._(tcp|udp)\.local/)) {
                    svctype = substr(target, RSTART, RLENGTH)
                    sub(/\.local$/, "", svctype)
                    instname = substr(target, 1, RSTART - 1)
                    if (length(instname) && substr(instname, length(instname)) == ".")
                        instname = substr(instname, 1, length(instname) - 1)
                    gsub(/\\032/, " ", instname)
                    if (src != "")
                        print src "|" "" "|" svctype "|" instname
                }
            }
        }
    }

    # A records — hostname to IP binding
    /\.local\. A [0-9]/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "A" && i < NF && $(i+1) ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
                ip = $(i+1)
                host = $(i-1)
                sub(/\.local\.$/, "", host)
                sub(/\.$/, "", host)
                print "ARECORD|" ip "|" host
            }
        }
    }

    # SRV records — hostname for a service instance
    /SRV [a-zA-Z].*\.local\.:[0-9]/ {
        for (i = 1; i <= NF; i++) {
            if ($i == "SRV" && i < NF) {
                srv = $(i+1)
                sub(/\.local\.:[0-9]+$/, "", srv)
                sub(/\.$/, "", srv)
                if (src != "" && srv != "")
                    print "SRVHOST|" src "|" srv
            }
        }
    }
    '
}

# ─── Aggregate entries into per-IP data structures ────────────────────────────
# Input: stream of  IP|HOSTNAME|SVC_TYPE|INSTANCE_NAME
#         and       ARECORD|IP|HOSTNAME
#         and       SRVHOST|SRC_IP|HOSTNAME
aggregate() {
    local infile="$1"
    [[ -s "$infile" ]] || return

    # First pass: collect A record mappings (IP → hostname)
    declare -gA A_HOSTNAME   # IP → hostname from A records
    while IFS='|' read -r f1 f2 f3 _rest; do
        [[ "$f1" == "ARECORD" ]] && A_HOSTNAME["$f2"]="$f3"
    done < "$infile"

    # Second pass: collect SRV host hints (src_ip → hostname)
    declare -gA SRV_HOSTNAME
    while IFS='|' read -r f1 f2 f3 _rest; do
        [[ "$f1" == "SRVHOST" ]] && SRV_HOSTNAME["$f2"]="$f3"
    done < "$infile"

    # Third pass: aggregate service entries
    declare -gA DEV_HOSTNAME
    declare -gA DEV_SERVICES   # space-separated unique service types
    declare -gA DEV_INSTANCES  # space-separated unique instance names
    declare -gA DEV_SVC_COUNT  # total service entry count

    while IFS='|' read -r ip host svctype instance; do
        # Skip special lines already handled
        [[ "$ip" == "ARECORD" || "$ip" == "SRVHOST" ]] && continue
        [[ -z "$ip" || -z "$svctype" ]] && continue
        # Skip IPv6
        [[ "$ip" =~ : ]] && continue

        # Hostname: prefer avahi-provided, then A record lookup, then SRV hint
        if [[ -n "$host" ]]; then
            DEV_HOSTNAME["$ip"]="$host"
        elif [[ -z "${DEV_HOSTNAME[$ip]+_}" ]]; then
            local fallback="${A_HOSTNAME[$ip]:-${SRV_HOSTNAME[$ip]:-}}"
            DEV_HOSTNAME["$ip"]="${fallback}"
        fi

        # Accumulate unique service types
        if [[ -z "${DEV_SERVICES[$ip]+_}" ]]; then
            DEV_SERVICES["$ip"]="$svctype"
        elif ! echo "${DEV_SERVICES[$ip]}" | grep -qF "$svctype"; then
            DEV_SERVICES["$ip"]+=" $svctype"
        fi

        # Accumulate unique instance names
        if [[ -z "${DEV_INSTANCES[$ip]+_}" ]]; then
            DEV_INSTANCES["$ip"]="$instance"
        elif ! echo "${DEV_INSTANCES[$ip]}" | grep -qF "$instance"; then
            DEV_INSTANCES["$ip"]+=" $instance"
        fi

        DEV_SVC_COUNT["$ip"]=$(( ${DEV_SVC_COUNT[$ip]:-0} + 1 ))
    done < "$infile"
}

# ─── Display ──────────────────────────────────────────────────────────────────
display_results() {
    local parsed="$1"

    if [[ ! -s "$parsed" ]]; then
        echo -e "\n${YLW}[!] No mDNS entries captured.${RST}"
        echo -e "${DIM}    Try a longer duration (-d 60) or check that devices are active.${RST}"
        echo -e "${DIM}    Also verify avahi-daemon is running: sudo systemctl status avahi-daemon${RST}"
        return
    fi

    aggregate "$parsed"

    local total_hosts="${#DEV_SERVICES[@]}"

    if [[ $total_hosts -eq 0 ]]; then
        echo -e "\n${YLW}[!] No devices resolved from capture.${RST}"
        return
    fi

    # ── Verbose: raw entry dump ──────────────────────────────────────────────
    if $VERBOSE; then
        echo
        echo -e "${BOLD}${WHT}Raw mDNS Entries:${RST}"
        printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..90})"
        printf "${BOLD}${BLU}%-16s %-28s %-30s %s${RST}\n" \
            "Source IP" "Service Type" "Instance Name" "Hostname"
        printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..90})"
        grep -v '^ARECORD\|^SRVHOST' "$parsed" | while IFS='|' read -r ip host svc inst; do
            [[ -z "$ip" || -z "$svc" ]] && continue
            [[ "$ip" =~ : ]] && continue
            printf "%-16s %-28s %-30s %s\n" "$ip" "$svc" "${inst:0:29}" "$host"
        done
        echo
    fi

    # ── Main results table ───────────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}╔══════════════════════════════════════════════════════════════════════════╗${RST}"
    echo -e "${BOLD}${WHT}║         mDNS / BONJOUR DEVICE DISCOVERY — Home Lab Report              ║${RST}"
    echo -e "${BOLD}${WHT}╚══════════════════════════════════════════════════════════════════════════╝${RST}"
    echo -e "  ${DIM}Backend used   : ${WHT}${BACKEND}${RST}"
    echo -e "  ${DIM}Listen duration: ${WHT}${CAPTURE_DURATION}s${RST}"
    echo -e "  ${DIM}Devices found  : ${WHT}${total_hosts}${RST}"
    echo

    printf "${BOLD}${BLU}%-16s %-19s %-26s %-26s %s${RST}\n" \
        "IP Address" "MAC Address" "Hostname" "Device Type" "Advertised Services"
    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..110})"

    # Sort by IP for clean output
    for ip in $(echo "${!DEV_SERVICES[@]}" \
                | tr ' ' '\n' \
                | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n); do

        local mac hostname services instances device_label cat col

        mac=$(mac_for_ip "$ip")
        hostname="${DEV_HOSTNAME[$ip]:-<unknown>}"
        services="${DEV_SERVICES[$ip]}"
        instances="${DEV_INSTANCES[$ip]:-}"

        # Infer device type
        local inferred
        inferred=$(infer_device "$services" "$hostname")
        IFS='|' read -r device_label cat <<< "$inferred"
        col=$(category_color "$cat")

        # Build short services display  (_airplay._tcp → airplay)
        local svc_short
        svc_short=$(echo "$services" \
            | tr ' ' '\n' \
            | while read -r s; do short_svc "$s"; done \
            | sort -u \
            | paste -sd ', ')

        printf "%-16s %-19s %-26s ${col}%-26s${RST} %s\n" \
            "$ip" "$mac" "${hostname:0:25}" "${device_label:0:25}" "${svc_short:0:50}"

        # If verbose, show instance names under each device
        if $VERBOSE && [[ -n "$instances" ]]; then
            echo "$instances" | tr ' ' '\n' | while read -r inst; do
                [[ -z "$inst" ]] && continue
                printf "%-16s %-19s %-26s %-26s ${DIM}  ↳ %s${RST}\n" \
                    "" "" "" "" "$inst"
            done
        fi
    done

    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..110})"

    # ── Service type frequency ───────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}Top Advertised Service Types:${RST}"
    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..55})"

    # Collect all service types across all devices
    local all_svcs=""
    for ip in "${!DEV_SERVICES[@]}"; do
        all_svcs+="${DEV_SERVICES[$ip]} "
    done

    echo "$all_svcs" | tr ' ' '\n' | grep -v '^$' | sort | uniq -c | sort -rn | head -15 \
        | while read -r count svc; do
            local friendly=""
            for entry in "${SERVICE_PATTERNS[@]}"; do
                local pat lbl _c
                IFS='|' read -r pat lbl _c <<< "$entry"
                if [[ "$svc" == "$pat" ]]; then
                    friendly=" ${DIM}(${lbl})${RST}"
                    break
                fi
            done
            printf "  ${CYN}%3s${RST}  %-30s%b\n" "$count" "$(short_svc "$svc")" "$friendly"
        done

    # ── Device category summary ──────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}Device Category Summary:${RST}"
    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..55})"

    declare -A CAT_COUNT
    for ip in "${!DEV_SERVICES[@]}"; do
        local inf cat_only
        inf=$(infer_device "${DEV_SERVICES[$ip]}" "${DEV_HOSTNAME[$ip]:-}")
        cat_only=$(echo "$inf" | cut -d'|' -f2)
        CAT_COUNT["$cat_only"]=$(( ${CAT_COUNT[$cat_only]:-0} + 1 ))
    done

    for cat in $(echo "${!CAT_COUNT[@]}" | tr ' ' '\n' | sort); do
        local col
        col=$(category_color "$cat")
        printf "  ${col}%-20s${RST} : %d device(s)\n" "$cat" "${CAT_COUNT[$cat]}"
    done

    echo
    echo -e "${DIM}  Note: Identification is heuristic — based on advertised mDNS service types.${RST}"
    echo -e "${DIM}  Devices with no mDNS activity or only _device-info._tcp will show as Unknown.${RST}"
    echo
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
while getopts ":i:d:b:vh" opt; do
    case $opt in
        i) INTERFACE="$OPTARG" ;;
        d) CAPTURE_DURATION="$OPTARG" ;;
        b) BACKEND="$OPTARG" ;;
        v) VERBOSE=true ;;
        h) usage ;;
        :) echo -e "${RED}[!] Option -$OPTARG requires an argument.${RST}"; exit 1 ;;
        \?) echo -e "${RED}[!] Unknown option: -$OPTARG${RST}"; usage ;;
    esac
done

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYN}mdns-analyzer.sh${RST} — mDNS / Bonjour Discovery Analyzer"
echo -e "${DIM}For authorized use on networks you own or have permission to analyze.${RST}"

check_deps

# Unified temp file for parsed entries
PARSED="/tmp/mdns_parsed_$$.txt"
trap 'rm -f "$AVAHI_OUT" "$PCAP_FILE" "$PARSED"' EXIT

echo -e "${DIM}[*] Using backend: ${BOLD}${BACKEND}${RST}"

case "$BACKEND" in
    avahi)
        run_avahi
        echo -e "${CYN}[*] Parsing avahi output...${RST}"
        parse_avahi "$AVAHI_OUT" > "$PARSED" || true
        ;;
    tcpdump)
        run_tcpdump
        if [[ ! -s "$PCAP_FILE" ]]; then
            echo -e "${RED}[!] Capture file is empty. Check interface and permissions.${RST}"
            exit 1
        fi
        echo -e "${CYN}[*] Parsing captured packets...${RST}"
        parse_tcpdump > "$PARSED" || true
        ;;
esac

# Build ARP table after capture so MAC lookups reflect devices seen during the session
build_arp_table
display_results "$PARSED"
