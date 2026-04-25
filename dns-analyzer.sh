#!/usr/bin/env bash
# dns-analyzer.sh — Educational DNS traffic analyzer for home lab use
# Captures DNS queries, identifies device types, and displays results in a table.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
CAPTURE_DURATION=60
CAPTURE_FILE="/tmp/dns_capture_$$.pcap"
PARSED_FILE="/tmp/dns_parsed_$$.txt"
INTERFACE=""
VERBOSE=false

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

# ─── Device fingerprint patterns ──────────────────────────────────────────────
# Format: "pattern|Device Type|OS"
declare -a DEVICE_PATTERNS=(
    # Apple / iOS / macOS
    "apple\.com|Apple Device|macOS/iOS"
    "icloud\.com|Apple Device|macOS/iOS"
    "mzstatic\.com|Apple Device|macOS/iOS"
    "akadns\.net|Apple Device|macOS/iOS"
    "aaplimg\.com|Apple Device|macOS/iOS"
    "apple-dns\.net|Apple Device|macOS/iOS"
    "push\.apple\.com|Apple Device|iOS"
    "appattest\.apple\.com|Apple Device|iOS"
    "ls\.apple\.com|Apple Device|macOS/iOS"

    # Google / Android
    "googleapis\.com|Android Device|Android"
    "android\.com|Android Device|Android"
    "gvt1\.com|Android Device|Android"
    "gvt2\.com|Android Device|Android"
    "play\.google\.com|Android Device|Android"
    "connectivitycheck\.gstatic\.com|Android Device|Android"
    "clients[0-9]*\.google\.com|Android Device|Android"
    "mtalk\.google\.com|Android Device|Android"
    "fcm\.googleapis\.com|Android Device|Android"

    # Microsoft / Windows
    "windowsupdate\.com|Windows PC|Windows"
    "microsoft\.com|Windows PC|Windows"
    "msftconnecttest\.com|Windows PC|Windows"
    "msftncsi\.com|Windows PC|Windows"
    "windows\.com|Windows PC|Windows"
    "xbox\.com|Windows PC|Windows"
    "live\.com|Windows PC|Windows"
    "microsoftonline\.com|Windows PC|Windows"
    "office365\.com|Windows PC|Windows"
    "azure\.com|Windows PC|Windows"

    # Amazon / Echo / Fire
    "amazon\.com|Amazon Device|Fire OS/Echo"
    "amazontrust\.com|Amazon Device|Fire OS/Echo"
    "amazonaws\.com|Amazon Device|Fire OS/Echo"
    "device-metrics-us\.amazon\.com|Amazon Echo|Echo"
    "alexa\.amazon\.com|Amazon Echo|Echo"

    # Smart TV / Streaming
    "netflix\.com|Streaming Device|Smart TV/Roku/etc."
    "nflxvideo\.net|Streaming Device|Smart TV/Roku/etc."
    "roku\.com|Roku Device|Roku"
    "samsungcloud\.com|Samsung Device|Smart TV/Samsung"
    "samsungcloudsolution\.com|Samsung Device|Smart TV/Samsung"
    "lgtvsdp\.com|LG Smart TV|webOS"
    "lgappstv\.com|LG Smart TV|webOS"

    # IoT / Smart Home
    "ring\.com|Ring Device|IoT"
    "nest\.com|Google Nest|IoT"
    "philips\.com|Philips Hue|IoT"
    "meethue\.com|Philips Hue|IoT"
    "tuya\.com|Tuya IoT Device|IoT"
    "tuyaus\.com|Tuya IoT Device|IoT"
    "particle\.io|IoT Device|IoT"

    # Gaming Consoles
    "playstation\.net|PlayStation|PS4/PS5"
    "playstation\.com|PlayStation|PS4/PS5"
    "nintendo\.net|Nintendo Switch|Switch"
    "nintendowifi\.net|Nintendo Switch|Switch"
    "xboxlive\.com|Xbox|Xbox"

    # Linux / General
    "ubuntu\.com|Linux PC|Ubuntu"
    "debian\.org|Linux PC|Debian"
    "fedoraproject\.org|Linux PC|Fedora"
    "archlinux\.org|Linux PC|Arch"
    "snap\.snapcraft\.io|Linux PC|Ubuntu/Snap"

    # Printers / Network Equipment
    "hp\.com|HP Printer|Printer"
    "hpcloud\.com|HP Printer|Printer"
    "epson\.com|Epson Printer|Printer"
    "brother\.com|Brother Printer|Printer"
)

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}dns-analyzer.sh${RST} — Educational DNS Traffic Analyzer

${BOLD}Usage:${RST}
  sudo $0 [OPTIONS]

${BOLD}Options:${RST}
  -i <iface>     Network interface to capture on (required for live mode)
  -f <file>      Analyze existing pcap file instead of live capture
  -d <seconds>   Capture duration in seconds (default: ${CAPTURE_DURATION})
  -v             Verbose: show all parsed DNS entries before summary
  -h             Show this help

${BOLD}Examples:${RST}
  sudo $0 -i eth0
  sudo $0 -i wlan0 -d 120
  sudo $0 -f capture.pcap
  sudo $0 -i wlan0 -v

${BOLD}Notes:${RST}
  - Requires tcpdump and arp to be installed
  - Must be run as root (or with sudo) for live capture
  - Only captures DNS query traffic (UDP port 53)
  - For use on networks you own or have explicit permission to analyze
EOF
    exit 0
}

# ─── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in tcpdump arp awk grep sed column; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}[!] Missing required tools: ${missing[*]}${RST}"
        echo -e "${DIM}    Install with: sudo apt install tcpdump net-tools${RST}"
        exit 1
    fi
}

# ─── Interface listing ────────────────────────────────────────────────────────
list_interfaces() {
    echo -e "${CYN}Available network interfaces:${RST}"
    ip -o link show 2>/dev/null \
        | awk -F': ' '{print "  " $2}' \
        | grep -v '^  lo$' \
        || ifconfig -a 2>/dev/null | grep -E '^[a-z]' | awk '{print "  " $1}' | tr -d ':'
}

# ─── ARP table lookup ─────────────────────────────────────────────────────────
# Build associative array: IP -> MAC
declare -A ARP_TABLE

build_arp_table() {
    while IFS= read -r line; do
        local ip mac
        ip=$(echo "$line" | grep -oP '\(\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(?=\))')
        mac=$(echo "$line" | grep -oP '([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}')
        if [[ -n "$ip" && -n "$mac" ]]; then
            ARP_TABLE["$ip"]="${mac,,}"
        fi
    done < <(arp -n 2>/dev/null || true)
}

mac_for_ip() {
    local ip="$1"
    echo "${ARP_TABLE[$ip]:-<unknown>}"
}

# ─── Device fingerprinting ────────────────────────────────────────────────────
identify_device() {
    local domains="$1"
    local best_type="Unknown"
    local best_os="Unknown"

    for pattern_entry in "${DEVICE_PATTERNS[@]}"; do
        local pat dev os
        IFS='|' read -r pat dev os <<< "$pattern_entry"
        if echo "$domains" | grep -qiE "$pat"; then
            best_type="$dev"
            best_os="$os"
            break
        fi
    done

    echo "${best_type}|${best_os}"
}

# ─── Live capture ─────────────────────────────────────────────────────────────
run_capture() {
    local iface="$1"
    local duration="$2"

    echo -e "\n${BOLD}${CYN}[*] Starting DNS capture on ${iface} for ${duration} seconds...${RST}"
    echo -e "${DIM}    Press Ctrl+C to stop early and view results.${RST}\n"

    # Spinner while capturing
    local spin_chars='|/-\'
    local i=0

    tcpdump -i "$iface" -w "$CAPTURE_FILE" \
        "udp port 53" \
        --snapshot-length=0 \
        -G "$duration" -W 1 \
        2>/dev/null &
    local tcpdump_pid=$!

    local elapsed=0
    while kill -0 "$tcpdump_pid" 2>/dev/null && [[ $elapsed -lt $duration ]]; do
        printf "\r  ${YLW}Capturing... [%s] %ds / %ds${RST}" \
            "${spin_chars:$((i % 4)):1}" "$elapsed" "$duration"
        sleep 1
        ((elapsed++)) || true
        ((i++)) || true
    done

    wait "$tcpdump_pid" 2>/dev/null || true
    printf "\r${GRN}  [+] Capture complete (%ds).%s${RST}\n" "$elapsed" "          "
}

# ─── Parse pcap ───────────────────────────────────────────────────────────────
# Output format per line: TIMESTAMP|SRC_IP|DOMAIN
parse_capture() {
    local pcap="$1"

    tcpdump -r "$pcap" -n -tt \
        "udp port 53 and (udp[10] & 0x80) == 0" \
        2>/dev/null \
    | awk '
        {
            # Timestamp is field 1
            ts = $1

            # Find source IP (field 3 = src.port, field 5 = dst.port)
            split($3, src, ".")
            # Reconstruct IP from first 4 octets of dotted-notation with port
            n = split($3, parts, ".")
            src_ip = parts[1] "." parts[2] "." parts[3] "." parts[4]

            # Extract queried domain: look for "A?" or "AAAA?" pattern
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^A\?$/ || $i ~ /^AAAA\?$/ || $i ~ /^A6\?$/) {
                    domain = $(i+1)
                    # Strip trailing dot
                    sub(/\.$/, "", domain)
                    if (domain != "" && domain != "0.0.0.0") {
                        printf "%s|%s|%s\n", ts, src_ip, domain
                    }
                }
            }
        }
    '
}

# ─── Aggregate and display ────────────────────────────────────────────────────
display_results() {
    local parsed="$1"

    if [[ ! -s "$parsed" ]]; then
        echo -e "\n${YLW}[!] No DNS query entries found in capture.${RST}"
        echo -e "${DIM}    Try a longer capture duration or check the interface.${RST}"
        return
    fi

    # Build associative arrays: IP -> set of domains, IP -> query count
    declare -A IP_DOMAINS
    declare -A IP_COUNT
    declare -A IP_FIRST_SEEN
    declare -A IP_LAST_SEEN

    while IFS='|' read -r ts src_ip domain; do
        [[ -z "$src_ip" || -z "$domain" ]] && continue

        # Accumulate unique domains per IP (space-separated)
        if [[ -z "${IP_DOMAINS[$src_ip]+_}" ]]; then
            IP_DOMAINS["$src_ip"]="$domain"
            IP_FIRST_SEEN["$src_ip"]="$ts"
        else
            # Only add if not already in the list
            if ! echo "${IP_DOMAINS[$src_ip]}" | grep -qw "$domain"; then
                IP_DOMAINS["$src_ip"]+=" $domain"
            fi
        fi
        IP_COUNT["$src_ip"]=$(( ${IP_COUNT[$src_ip]:-0} + 1 ))
        IP_LAST_SEEN["$src_ip"]="$ts"
    done < "$parsed"

    local total_queries
    total_queries=$(wc -l < "$parsed")
    local total_hosts="${#IP_DOMAINS[@]}"

    # ── Header ──────────────────────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}╔══════════════════════════════════════════════════════════════════════╗${RST}"
    echo -e "${BOLD}${WHT}║            DNS TRAFFIC ANALYSIS — Home Lab Report                   ║${RST}"
    echo -e "${BOLD}${WHT}╚══════════════════════════════════════════════════════════════════════╝${RST}"
    echo -e "  ${DIM}Total DNS queries captured : ${WHT}${total_queries}${RST}"
    echo -e "  ${DIM}Unique source hosts        : ${WHT}${total_hosts}${RST}"
    echo

    # ── Per-host table ───────────────────────────────────────────────────────
    printf "${BOLD}${BLU}%-18s %-19s %-24s %-8s %-22s${RST}\n" \
        "Source IP" "MAC Address" "Device Type (OS)" "Queries" "Sample Domains"
    printf "${DIM}%s${RST}\n" \
        "$(printf '─%.0s' {1..100})"

    for ip in $(echo "${!IP_DOMAINS[@]}" | tr ' ' '\n' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n); do
        local mac domains device_info device_type device_os count sample
        mac=$(mac_for_ip "$ip")
        domains="${IP_DOMAINS[$ip]}"
        count="${IP_COUNT[$ip]}"

        device_info=$(identify_device "$domains")
        IFS='|' read -r device_type device_os <<< "$device_info"

        # Pick up to 3 sample domains for display
        sample=$(echo "$domains" | tr ' ' '\n' | head -3 | paste -sd ',' | sed 's/,/, /g')
        local total_unique
        total_unique=$(echo "$domains" | wc -w)

        # Color-code by device type
        local type_color="$RST"
        case "$device_type" in
            "Apple Device")    type_color="$MAG" ;;
            "Android Device")  type_color="$GRN" ;;
            "Windows PC")      type_color="$BLU" ;;
            "Amazon"*)         type_color="$YLW" ;;
            "Linux PC")        type_color="$CYN" ;;
            "Unknown")         type_color="$RED" ;;
            *)                 type_color="$WHT" ;;
        esac

        printf "%-18s %-19s ${type_color}%-24s${RST} %-8s %-22s\n" \
            "$ip" "$mac" "${device_type} (${device_os})" "${count}q" "$sample"

        # Show remaining domains if verbose
        if $VERBOSE && [[ $total_unique -gt 3 ]]; then
            local rest
            rest=$(echo "$domains" | tr ' ' '\n' | tail -n +4)
            while IFS= read -r d; do
                printf "%-18s %-19s %-24s %-8s ${DIM}%s${RST}\n" \
                    "" "" "" "" "  + $d"
            done <<< "$rest"
        fi
    done

    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..100})"

    # ── Domain query frequency ───────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}Top 15 Queried Domains:${RST}"
    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..50})"

    awk -F'|' 'NF>=3{print $3}' "$parsed" \
        | sort | uniq -c | sort -rn | head -15 \
        | awk '{printf "  %-6s %s\n", $1, $2}' \
        | while IFS= read -r line; do
            local count_val
            count_val=$(echo "$line" | awk '{print $1}')
            echo -e "  ${CYN}${count_val}${RST}$(echo "$line" | cut -c$((${#count_val}+3))-)"
          done

    # ── Device type summary ──────────────────────────────────────────────────
    echo
    echo -e "${BOLD}${WHT}Device Type Summary:${RST}"
    printf "${DIM}%s${RST}\n" "$(printf '─%.0s' {1..50})"

    declare -A TYPE_COUNT
    for ip in "${!IP_DOMAINS[@]}"; do
        local d_info d_type
        d_info=$(identify_device "${IP_DOMAINS[$ip]}")
        d_type=$(echo "$d_info" | cut -d'|' -f1)
        TYPE_COUNT["$d_type"]=$(( ${TYPE_COUNT[$d_type]:-0} + 1 ))
    done

    for dtype in $(echo "${!TYPE_COUNT[@]}" | tr ' ' '\n' | sort); do
        printf "  %-28s : %d host(s)\n" "$dtype" "${TYPE_COUNT[$dtype]}"
    done

    echo
    echo -e "${DIM}  Note: Device identification is heuristic and based solely on DNS query patterns.${RST}"
    echo -e "${DIM}  Accuracy depends on capture duration and device activity level.${RST}"
    echo
}

# ─── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    rm -f "$CAPTURE_FILE" "$PARSED_FILE"
}
trap cleanup EXIT

# ─── Argument parsing ─────────────────────────────────────────────────────────
PCAP_FILE=""

while getopts ":i:f:d:vh" opt; do
    case $opt in
        i) INTERFACE="$OPTARG" ;;
        f) PCAP_FILE="$OPTARG" ;;
        d) CAPTURE_DURATION="$OPTARG" ;;
        v) VERBOSE=true ;;
        h) usage ;;
        :) echo -e "${RED}[!] Option -$OPTARG requires an argument.${RST}"; exit 1 ;;
        \?) echo -e "${RED}[!] Unknown option: -$OPTARG${RST}"; usage ;;
    esac
done

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYN}dns-analyzer.sh${RST} — Educational DNS Traffic Analyzer"
echo -e "${DIM}For authorized use on networks you own or have permission to analyze.${RST}"

check_deps
build_arp_table

if [[ -n "$PCAP_FILE" ]]; then
    # ── Offline mode ──────────────────────────────────────────────────────
    if [[ ! -f "$PCAP_FILE" ]]; then
        echo -e "${RED}[!] File not found: $PCAP_FILE${RST}"
        exit 1
    fi
    echo -e "\n${CYN}[*] Parsing pcap file: ${PCAP_FILE}${RST}"
    parse_capture "$PCAP_FILE" > "$PARSED_FILE"

elif [[ -n "$INTERFACE" ]]; then
    # ── Live capture mode ─────────────────────────────────────────────────
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Live capture requires root. Run with sudo.${RST}"
        exit 1
    fi

    # Verify interface exists
    if ! ip link show "$INTERFACE" &>/dev/null 2>&1; then
        echo -e "${RED}[!] Interface '$INTERFACE' not found.${RST}"
        list_interfaces
        exit 1
    fi

    # Handle Ctrl+C gracefully
    trap 'echo -e "\n${YLW}[!] Interrupted — analyzing partial capture...${RST}"; sleep 1' INT

    run_capture "$INTERFACE" "$CAPTURE_DURATION"

    if [[ ! -s "$CAPTURE_FILE" ]]; then
        echo -e "${RED}[!] Capture file is empty. Check interface and permissions.${RST}"
        exit 1
    fi

    echo -e "${CYN}[*] Parsing captured packets...${RST}"
    parse_capture "$CAPTURE_FILE" > "$PARSED_FILE"

else
    # ── No mode selected ──────────────────────────────────────────────────
    echo -e "\n${RED}[!] No interface or file specified.${RST}"
    list_interfaces
    echo
    usage
fi

display_results "$PARSED_FILE"
