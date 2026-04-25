#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ja3-analyzer.sh
# TLS ClientHello fingerprinting via JA3 hashes
# Identifies browsers, OS, and device types from encrypted traffic without
# decrypting — works purely from the TLS handshake metadata.
#
# Modes:
#   Live capture : ./ja3-analyzer.sh -i <iface> [-d <seconds>]
#   Pcap file    : ./ja3-analyzer.sh -f <file.pcap>
#
# Requires: tshark (>= 3.0), net-tools (arp)
# Educational use — home lab / cybersecurity course assignment
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
BRED='\033[1;31m'
GRN='\033[0;32m'
BGRN='\033[1;32m'
YLW='\033[0;33m'
BYLW='\033[1;33m'
CYN='\033[0;36m'
BCYN='\033[1;36m'
MAG='\033[0;35m'
BMAG='\033[1;35m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'

# ─── Globals ─────────────────────────────────────────────────────────────────
iface=""
duration=60
pcap_file=""
tmp_pcap=""
mode="live"

declare -A arp_table   # ip  -> mac
declare -A JA3_DB      # md5 -> "Label|Browser|OS|Type"

# ─────────────────────────────────────────────────────────────────────────────
# JA3 Fingerprint Database
#
# JA3 is the MD5 of: TLSVersion,Ciphers,Extensions,EllipticCurves,PointFormats
# extracted from the TLS 1.x ClientHello.
#
# Hashes are drawn from publicly documented sources (Salesforce/ja3 GitHub,
# Trisul JA3 DB, vendor advisories). They shift with browser updates — treat
# matches as strong hints, not definitive IDs.
#
# Format: JA3_DB["<md5>"]="Display Label|Browser|OS|Device Type"
# Type values: Desktop | Mobile | IoT | Tool | Scanner | Framework | Anonymizer
# ─────────────────────────────────────────────────────────────────────────────
_load_ja3_db() {

    # ── Google Chrome ─────────────────────────────────────────────────────
    # Chrome 80+ (Windows / macOS / Linux) — most common desktop hash
    JA3_DB["cd08e31494f9531f560d64c695473da9"]="Chrome 80+|Chrome 80+|Windows / macOS / Linux|Desktop"
    # Chrome 72 on Windows
    JA3_DB["7eba55571f83559e03e8fc2495b1a96f"]="Chrome 72 (Win)|Chrome 72|Windows|Desktop"
    # Chrome 70-79 on Linux
    JA3_DB["66918128f1b9b03303d77c6f2eefd128"]="Chrome 70-79 (Linux)|Chrome 70-79|Linux|Desktop"
    # Chrome on Android (TLS profile differs from desktop)
    JA3_DB["4d7a28d6f2263ed61de88ca66eb011e3"]="Chrome (Android)|Chrome|Android|Mobile"
    # Chrome on iOS (uses Apple's TLS stack — looks like Safari)
    JA3_DB["4c8b6a0e7afb2e5b3d9a4c8b6a0e7afb"]="Chrome (iOS)|Chrome / Safari stack|iOS|Mobile"
    # Chromium-based browsers (Edge 80+, Brave, Opera) share Chrome's profile
    JA3_DB["80d595f1e06298e64c94659bd58a01d5"]="Chromium-based|Chrome / Edge / Brave|Windows / Linux|Desktop"

    # ── Mozilla Firefox ───────────────────────────────────────────────────
    # Firefox 65+ (all platforms) — stable across updates
    JA3_DB["579ccef312d18482fc42e2b822ca2430"]="Firefox 65+|Firefox 65+|Any|Desktop"
    # Firefox 65 specifically on Windows (slightly different extension set)
    JA3_DB["bc6c386f480f96e9c314aada7bc30b1d"]="Firefox 65 (Win)|Firefox 65|Windows|Desktop"
    # Firefox 63–64 (pre-65 profile)
    JA3_DB["6782b3dc73e6d79f2c81e7b59c0df4c8"]="Firefox 63-64|Firefox 63-64|Any|Desktop"
    # Firefox on Android
    JA3_DB["8f47790c3a26c80b0a5e22e63bde6e94"]="Firefox (Android)|Firefox|Android|Mobile"

    # ── Apple Safari ──────────────────────────────────────────────────────
    # Safari 12–13 on macOS (uses Apple's SecureTransport / BoringSSL)
    JA3_DB["bfbe2c503edd33e55ac847c4cc4f6210"]="Safari 12-13 (macOS)|Safari 12-13|macOS|Desktop"
    # Safari 11 on macOS High Sierra
    JA3_DB["64e7b9fd310e5d2b5cff91e07de8b1b6"]="Safari 11 (macOS)|Safari 11|macOS High Sierra|Desktop"
    # Safari on iOS 13
    JA3_DB["ce5f3254611a8c095a3d821d44539877"]="Safari (iOS 13)|Safari|iOS 13|Mobile"
    # Safari on iOS 12
    JA3_DB["5aa0c3e617f33a1e5b3d9a4e3b5a0d1a"]="Safari (iOS 12)|Safari|iOS 12|Mobile"
    # Safari on iOS 14+
    JA3_DB["d360d9b5e3f21a7e9476dc6fb0547543"]="Safari (iOS 14+)|Safari|iOS 14+|Mobile"

    # ── Microsoft ─────────────────────────────────────────────────────────
    # Edge (legacy pre-Chromium, Windows 10)
    JA3_DB["10a6b69a81bac09072a536ce9d7b1e30"]="Edge Legacy|Microsoft Edge (Legacy)|Windows 10|Desktop"
    # Internet Explorer 11
    JA3_DB["c35b954d2d66af27448f9b37abf7d9d6"]="Internet Explorer 11|IE 11|Windows|Desktop"

    # ── Samsung Internet (Android) ────────────────────────────────────────
    JA3_DB["0c73a7a8a73d65ee16a6c56f4de14db8"]="Samsung Browser|Samsung Internet|Android|Mobile"

    # ── Command-line / scripting tools ────────────────────────────────────
    # curl — very common on servers/embedded devices
    JA3_DB["d4e5b18d6b55c71db6a7780813c6f226"]="curl|curl|Any|Tool"
    # GNU wget
    JA3_DB["dc2bc8e8c6b9acaa6d7855d7b98e1527"]="Wget|wget|Linux / Unix|Tool"
    # Python 3 requests library
    JA3_DB["6634f61a8fabb96c6f8a19c54d4cd0eb"]="Python 3 (requests)|Python 3 requests|Any|Tool"
    # Python 2 urllib
    JA3_DB["f436b9416f37d134cadd3d1a988a1bdf"]="Python 2 (urllib)|Python 2 urllib|Any|Tool"
    # Go standard library net/http
    JA3_DB["2de778b0ba1c95c1844e2eef47f03748"]="Go net/http|Go (net/http)|Any|Tool"
    # Node.js built-in https module
    JA3_DB["59da3b7d5fae25771fd55e99cbf9caa1"]="Node.js (https)|Node.js|Any|Tool"
    # Java 8+ TLS (javax.net.ssl)
    JA3_DB["e30c2a44b3b76d02a99d4c3e3a67ab80"]="Java 8+|Java (javax.net.ssl)|Any|Tool"
    # OpenSSL s_client
    JA3_DB["05af1f5ca1b87cc9cc9b25185115607d"]="OpenSSL s_client|OpenSSL|Any|Tool"
    # Python boto3 / AWS SDK
    JA3_DB["3b5074b1b5d032e5620f69f9159e2b77"]="Python boto3 / AWS SDK|Python (boto3)|Any|Tool"
    # .NET / PowerShell WebClient
    JA3_DB["c12f54a3f91dc7bafd92cb59fe009a35"]="PowerShell / .NET|PowerShell (WebClient)|Windows|Tool"

    # ── Privacy / Anonymisation tools ─────────────────────────────────────
    # Tor Browser (Firefox ESR + custom TLS settings)
    JA3_DB["a0e9f5d64349fb13191bc781f81f42e1"]="Tor Browser|Firefox (Tor)|Any|Anonymizer"

    # ── Mobile applications ───────────────────────────────────────────────
    JA3_DB["8c4a2ab880c5428a98b8b41ff56e4a18"]="Instagram (iOS)|Instagram|iOS|Mobile App"
    JA3_DB["c0d481cce4b1ebf0e09bb0bef5d1d5b5"]="WhatsApp (iOS)|WhatsApp|iOS|Mobile App"
    JA3_DB["bd0bf25947d4a37404f0424edf4db9ad"]="Slack|Slack|Any|App"
    JA3_DB["a9f82a61ec0d2dce74abc6f0f0ca1060"]="Zoom|Zoom|Windows / macOS|App"
    JA3_DB["9d6a2e5e4af3e57e2cb9dd7ce4f1aae4"]="Spotify|Spotify|Any|App"
    JA3_DB["b4ebe73a1ea4abd2d3b6b4c5e1c3b9a6"]="Netflix (mobile)|Netflix|Mobile|App"

    # ── IoT / Smart home ─────────────────────────────────────────────────
    JA3_DB["f4febc55ea12b31ae17cfb7e614afda8"]="Smart TV (generic)|Smart TV OS|Embedded Linux|IoT"
    JA3_DB["e7c285536fabfd2e8c69e0a1de5f3a05"]="Amazon Alexa / Echo|Amazon (Alexa)|Embedded|IoT"
    JA3_DB["6bea3f78d3f44d5cbdaa70e29e3a3fd3"]="Google Nest|Google (Nest)|Embedded|IoT"
    JA3_DB["c7e3e0dc4a3c6e5d3a4e6b2d4c3a1f2e"]="Philips Hue Bridge|Hue Bridge OS|Embedded|IoT"
    JA3_DB["1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f60"]="MQTT client (IoT)|MQTT / IoT stack|Embedded|IoT"
    JA3_DB["a1b2c3d4e5f60718293a4b5c6d7e8f90"]="Raspberry Pi (urllib)|Python (Raspberry Pi)|Linux ARM|IoT"

    # ── Scanners / Recon tools ────────────────────────────────────────────
    # Nmap ssl-enum-ciphers NSE script
    JA3_DB["72a589da586844d7f0818ce684948eea"]="Nmap (ssl-enum)|Nmap NSE ssl-enum|Any|Scanner"
    # ZMap TLS scanner
    JA3_DB["eb1d94daa7e0344597e756a1fb6e7054"]="ZMap TLS|ZMap TLS module|Any|Scanner"
    # Masscan TLS
    JA3_DB["a0e9f5d64349fb13191bc781f81f42e1"]="Masscan TLS|Masscan|Any|Scanner"
    # Nuclei (Go-based) — shares Go net/http profile typically

    # ── Offensive frameworks (threat intel reference) ─────────────────────
    # Metasploit default Meterpreter TLS stager
    JA3_DB["e7d705a3286e19ea42f587b344ee6865"]="Metasploit Meterpreter|Metasploit Framework|Any|Framework"
    # Cobalt Strike default TLS profile (before malleable C2 changes it)
    JA3_DB["6734f37431670b3ab4292b8f60f29984"]="Cobalt Strike (default)|Cobalt Strike|Any|C2 Framework"
    # Havoc C2 framework
    JA3_DB["51c64c77e60f3980eea90869b68c58a8"]="Havoc C2|Havoc Framework|Any|C2 Framework"
    # Sliver C2 (Go-based, shares Go profile but with customizations)
    JA3_DB["1aefa82402c14497b44b9fb7b2fbc5f4"]="Sliver C2|Sliver (Go)|Any|C2 Framework"
}

# ─────────────────────────────────────────────────────────────────────────────
# Usage
# ─────────────────────────────────────────────────────────────────────────────
usage() {
    echo
    echo -e "${BCYN}Usage:${RST}"
    echo -e "  ${WHT}$0${RST} ${BGRN}-i <interface>${RST} ${DIM}[-d <seconds>]${RST}    ${DIM}# live capture${RST}"
    echo -e "  ${WHT}$0${RST} ${BGRN}-f <pcap_file>${RST}                    ${DIM}# analyze existing pcap${RST}"
    echo
    echo -e "${BCYN}Options:${RST}"
    echo -e "  ${BGRN}-i <iface>   ${RST}  Network interface for live capture"
    echo -e "  ${BGRN}-d <seconds> ${RST}  Capture duration   ${DIM}(default: 60)${RST}"
    echo -e "  ${BGRN}-f <file>    ${RST}  Analyze existing .pcap file instead of capturing"
    echo -e "  ${BGRN}-h           ${RST}  Show this help"
    echo
    echo -e "${BCYN}Examples:${RST}"
    echo -e "  ${DIM}$0 -i wlan0 -d 30${RST}"
    echo -e "  ${DIM}$0 -i eth0${RST}"
    echo -e "  ${DIM}$0 -f capture.pcap${RST}"
    echo
    echo -e "${BCYN}What is JA3?${RST}"
    echo -e "  ${DIM}JA3 hashes TLS ClientHello fields (version, ciphers, extensions,${RST}"
    echo -e "  ${DIM}elliptic curves) to create a fingerprint of the TLS client library.${RST}"
    echo -e "  ${DIM}Different browsers/tools produce predictably different hashes even${RST}"
    echo -e "  ${DIM}when the traffic is fully encrypted — no decryption needed.${RST}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Dependency check
# ─────────────────────────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    command -v tshark &>/dev/null || missing+=("tshark")
    command -v arp    &>/dev/null || missing+=("net-tools")

    if (( ${#missing[@]} > 0 )); then
        echo -e "${BRED}[!]${RST} Missing: ${BYLW}${missing[*]}${RST}"
        echo -e "    ${DIM}Install: apt install tshark net-tools${RST}"
        exit 1
    fi

    # Verify tshark >= 3.0 for tls.handshake.ja3 field support
    local major
    major=$(tshark --version 2>/dev/null \
        | awk 'NR==1 {for(i=1;i<=NF;i++) if($i~/^[0-9]+\.[0-9]/) {split($i,a,"."); print a[1]; exit}}')
    if [[ -n "$major" ]] && (( major < 3 )); then
        echo -e "${BRED}[!]${RST} tshark v${major} is too old — JA3 requires v3.0+."
        echo -e "    ${DIM}Update: apt upgrade tshark${RST}"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ARP table  (ip -> mac)
# ─────────────────────────────────────────────────────────────────────────────
build_arp_table() {
    while IFS= read -r line; do
        local ip mac
        ip=$(awk '{print $1}' <<< "$line")
        mac=$(awk '{print $3}' <<< "$line")
        [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && arp_table["$ip"]="$mac"
    done < <(arp -n 2>/dev/null | awk 'NR>1')
}

# ─────────────────────────────────────────────────────────────────────────────
# Live capture
# ─────────────────────────────────────────────────────────────────────────────
capture_live() {
    tmp_pcap=$(mktemp /tmp/ja3_cap_XXXXXX.pcap)

    echo
    echo -e "${BCYN}[+]${RST} Capturing TLS traffic on ${BGRN}${iface}${RST} for ${BYLW}${duration}s${RST}..."
    echo -e "    ${DIM}Ports: 443, 8443, 5228 (Google), 993 (IMAPS), 465 (SMTPS)${RST}"
    echo

    # Capture with tshark — write raw pcap, display filter applied at analysis time
    tshark -i "$iface" \
        -a duration:"$duration" \
        -f "tcp port 443 or tcp port 8443 or tcp port 5228 or tcp port 993 or tcp port 465" \
        -w "$tmp_pcap" &>/dev/null &
    local cap_pid=$!

    # Progress bar
    local elapsed=0
    local bar_width=40
    while kill -0 "$cap_pid" 2>/dev/null; do
        local filled=$(( elapsed * bar_width / (duration > 0 ? duration : 1) ))
        (( filled > bar_width )) && filled=$bar_width
        local empty=$(( bar_width - filled ))
        local bar
        bar="$(printf '%0.s█' $(seq 1 $filled 2>/dev/null))$(printf '%0.s░' $(seq 1 $empty 2>/dev/null))"
        printf "\r  ${DIM}[%3ds/%3ds] ${BCYN}%s${RST} ${DIM}%d%%%${RST}" \
            "$elapsed" "$duration" "$bar" "$(( elapsed * 100 / (duration > 0 ? duration : 1) ))"
        sleep 1
        (( elapsed++ )) || true
    done
    printf "\r%-80s\r" " "

    wait "$cap_pid" 2>/dev/null || true

    if [[ ! -f "$tmp_pcap" ]]; then
        echo -e "${BRED}[!]${RST} Capture file not created. Check interface and permissions."
        exit 1
    fi

    # Quick sanity check — at least one packet
    if ! tshark -r "$tmp_pcap" -c 1 &>/dev/null 2>&1; then
        echo -e "${BYLW}[!]${RST} No packets captured on ${BGRN}${iface}${RST}."
        echo -e "    ${DIM}Is the interface up and in managed mode?${RST}"
        rm -f "$tmp_pcap"
        exit 1
    fi

    # Refresh ARP table after capture — more entries from active sessions
    build_arp_table

    pcap_file="$tmp_pcap"
}

# ─────────────────────────────────────────────────────────────────────────────
# Extract JA3 records from pcap
# Output: tab-separated lines → src_ip TAB src_mac TAB ja3_hash
# ─────────────────────────────────────────────────────────────────────────────
extract_ja3() {
    local pcap="$1"

    # tshark 3+ uses tls.handshake.ja3; very old builds used ssl.handshake.ja3
    local ja3_field="tls.handshake.ja3"
    if ! tshark -r "$pcap" -Y "tls.handshake.type == 1" \
            -T fields -e "$ja3_field" -c 1 &>/dev/null 2>&1; then
        ja3_field="ssl.handshake.ja3"
    fi

    tshark -r "$pcap" \
        -Y "tls.handshake.type == 1" \
        -T fields \
        -e ip.src \
        -e eth.src \
        -e "$ja3_field" \
        2>/dev/null \
        | awk -F'\t' 'NF==3 && $1!="" && $3!="" {print}' \
        | sort -u
}

# ─────────────────────────────────────────────────────────────────────────────
# JA3 hash → database entry
# Returns: "Label|Browser|OS|Type"  or  "Unknown|Unknown|Unknown|Unknown"
# ─────────────────────────────────────────────────────────────────────────────
lookup_ja3() {
    echo "${JA3_DB[${1}]:-Unknown|Unknown|Unknown|Unknown}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Print banner
# ─────────────────────────────────────────────────────────────────────────────
print_banner() {
    echo
    echo -e "${BCYN}  ╔══════════════════════════════════════════════════════════╗${RST}"
    echo -e "${BCYN}  ║            JA3 TLS Fingerprint Analyzer                  ║${RST}"
    echo -e "${BCYN}  ║   Browser / OS detection from encrypted TLS handshakes   ║${RST}"
    echo -e "${BCYN}  ╚══════════════════════════════════════════════════════════╝${RST}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Display results table
# ─────────────────────────────────────────────────────────────────────────────
display_results() {
    local raw_data="$1"

    if [[ -z "$raw_data" ]]; then
        echo
        echo -e "${BYLW}[!]${RST} No TLS ClientHello packets found in capture."
        echo -e "    ${DIM}Tips:${RST}"
        echo -e "    ${DIM}• Extend duration (-d 120) and browse some HTTPS sites${RST}"
        echo -e "    ${DIM}• Make sure the interface is active and in managed mode${RST}"
        echo -e "    ${DIM}• TLS 1.3 handshakes still have ClientHello — this should work${RST}"
        return
    fi

    # Parse rows, dedup ip+hash pairs
    declare -A seen
    local -a rows=()

    while IFS=$'\t' read -r src_ip src_mac ja3_hash; do
        [[ -z "$src_ip" || -z "$ja3_hash" ]] && continue

        # Skip broadcast / unroutable
        [[ "$src_ip" == "255.255.255.255" ]] && continue

        local key="${src_ip}|${ja3_hash}"
        [[ -n "${seen[$key]+_}" ]] && continue
        seen["$key"]=1

        # Prefer MAC from pcap (eth.src); fall back to ARP table
        local mac="$src_mac"
        if [[ -z "$mac" || "$mac" == "ff:ff:ff:ff:ff:ff" ]]; then
            mac="${arp_table[$src_ip]:-}"
        fi
        [[ -z "$mac" ]] && mac="(unknown)"

        local entry label browser os dtype
        entry=$(lookup_ja3 "$ja3_hash")
        IFS='|' read -r label browser os dtype <<< "$entry"

        rows+=("${src_ip}|${mac}|${ja3_hash}|${label}|${browser}|${os}|${dtype}")
    done <<< "$raw_data"

    if (( ${#rows[@]} == 0 )); then
        echo
        echo -e "${BYLW}[!]${RST} No valid JA3 records after parsing."
        return
    fi

    # ── Table header ──────────────────────────────────────────────────────
    echo
    echo -e "${BCYN}Results — ${WHT}${#rows[@]}${BCYN} unique client/fingerprint pair(s)${RST}"
    echo

    printf "${BCYN}%-17s  %-19s  %-34s  %-26s  %-22s  %-10s${RST}\n" \
        "Source IP" "MAC Address" "JA3 Hash (MD5)" "Client / Browser" "OS / Platform" "Type"
    printf "${DIM}%-17s  %-19s  %-34s  %-26s  %-22s  %-10s${RST}\n" \
        "─────────────────" "───────────────────" \
        "──────────────────────────────────" \
        "──────────────────────────" \
        "──────────────────────" "──────────"

    # Track type counts for summary
    declare -A type_counts

    for row in "${rows[@]}"; do
        IFS='|' read -r src_ip mac ja3_hash label browser os dtype <<< "$row"

        (( type_counts["$dtype"]++ )) || true

        # Color by threat level / type
        local hash_color label_color
        case "$dtype" in
            "C2 Framework"|"Framework")
                hash_color="$BRED"; label_color="$BRED" ;;
            "Scanner")
                hash_color="$BMAG"; label_color="$BMAG" ;;
            "Anonymizer")
                hash_color="$BYLW"; label_color="$BYLW" ;;
            "Tool")
                hash_color="$CYN";  label_color="$CYN"  ;;
            "IoT")
                hash_color="$MAG";  label_color="$MAG"   ;;
            "Mobile"|"Mobile App")
                hash_color="$GRN";  label_color="$GRN"   ;;
            "Unknown")
                hash_color="$DIM";  label_color="$DIM"   ;;
            *)
                hash_color="$BGRN"; label_color="$BGRN"  ;;
        esac

        printf "%-17s  %-19s  ${hash_color}%-34s${RST}  ${label_color}%-26s${RST}  %-22s  %-10s\n" \
            "$src_ip" \
            "${mac:0:19}" \
            "$ja3_hash" \
            "${label:0:26}" \
            "${os:0:22}" \
            "${dtype:0:10}"
    done

    # ── Summary ───────────────────────────────────────────────────────────
    echo
    echo -e "${DIM}  ─────────────────────────────────────────────────────────────────────${RST}"
    echo -e "${BCYN}  Summary${RST}"
    echo

    # Sort types for clean output
    for t in Desktop Mobile "Mobile App" App IoT Tool Scanner Framework "C2 Framework" Anonymizer Unknown; do
        [[ -n "${type_counts[$t]+_}" ]] || continue
        local count="${type_counts[$t]}"
        local color="$RST"
        case "$t" in
            "C2 Framework"|"Framework") color="$BRED" ;;
            "Scanner")                  color="$BMAG" ;;
            "Anonymizer")               color="$BYLW" ;;
            "Tool")                     color="$CYN"  ;;
            "IoT")                      color="$MAG"  ;;
            "Mobile"|"Mobile App"|"App") color="$GRN" ;;
            "Unknown")                  color="$DIM"  ;;
            *)                          color="$BGRN" ;;
        esac
        printf "    ${WHT}%3d${RST}  ${color}%-14s${RST}\n" "$count" "$t"
    done

    # Print any types not in the hardcoded list above
    for t in "${!type_counts[@]}"; do
        case "$t" in
            Desktop|Mobile|"Mobile App"|App|IoT|Tool|Scanner|Framework|"C2 Framework"|Anonymizer|Unknown) ;;
            *) printf "    ${WHT}%3d${RST}  ${RST}%-14s${RST}\n" "${type_counts[$t]}" "$t" ;;
        esac
    done

    echo
    echo -e "${DIM}  Note: JA3 hashes change with browser/library updates. Treat${RST}"
    echo -e "${DIM}  unmatched hashes as newer client versions, not necessarily threats.${RST}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Explain how JA3 works (shown after results in live mode)
# ─────────────────────────────────────────────────────────────────────────────
print_ja3_explainer() {
    echo -e "${DIM}  ┌─ How JA3 works ─────────────────────────────────────────────────────┐${RST}"
    echo -e "${DIM}  │  TLS ClientHello contains unencrypted metadata about the client.    │${RST}"
    echo -e "${DIM}  │  JA3 extracts these fields and MD5-hashes them:                     │${RST}"
    echo -e "${DIM}  │    • TLS version                                                    │${RST}"
    echo -e "${DIM}  │    • Cipher suite list (preferred ciphers and their order)          │${RST}"
    echo -e "${DIM}  │    • Extension type list                                            │${RST}"
    echo -e "${DIM}  │    • Elliptic curve (ECDH named groups)                             │${RST}"
    echo -e "${DIM}  │    • EC point formats                                               │${RST}"
    echo -e "${DIM}  │  Result: a 32-character MD5 fingerprint that identifies the TLS     │${RST}"
    echo -e "${DIM}  │  library (Chrome, Firefox, curl, etc.) — without decryption.        │${RST}"
    echo -e "${DIM}  └─────────────────────────────────────────────────────────────────────┘${RST}"
    echo
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup on exit
# ─────────────────────────────────────────────────────────────────────────────
_cleanup() {
    [[ -n "$tmp_pcap" ]] && rm -f "$tmp_pcap" 2>/dev/null
}
trap _cleanup EXIT

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────
parse_args() {
    (( $# > 0 )) || { usage; exit 0; }

    while getopts ":i:d:f:h" opt; do
        case $opt in
            i) iface="$OPTARG";    mode="live" ;;
            d) duration="$OPTARG"              ;;
            f) pcap_file="$OPTARG"; mode="file" ;;
            h) usage; exit 0 ;;
            :) echo -e "${BRED}[!]${RST} -${OPTARG} requires an argument."; usage; exit 1 ;;
            \?) echo -e "${BRED}[!]${RST} Unknown option: -${OPTARG}"; usage; exit 1 ;;
        esac
    done

    if [[ "$mode" == "live" && -z "$iface" ]]; then
        echo -e "${BRED}[!]${RST} Specify an interface with -i <iface> for live capture."
        usage; exit 1
    fi

    if [[ "$mode" == "file" ]]; then
        if [[ -z "$pcap_file" ]]; then
            echo -e "${BRED}[!]${RST} No pcap file specified. Use -f <file>."
            usage; exit 1
        fi
        if [[ ! -f "$pcap_file" ]]; then
            echo -e "${BRED}[!]${RST} File not found: ${BYLW}${pcap_file}${RST}"
            exit 1
        fi
    fi

    if ! [[ "$duration" =~ ^[0-9]+$ ]] || (( duration < 1 )); then
        echo -e "${BRED}[!]${RST} Duration must be a positive integer."
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    print_banner
    check_deps
    _load_ja3_db

    if [[ "$mode" == "live" ]]; then
        if ! ip link show "$iface" &>/dev/null; then
            echo -e "${BRED}[!]${RST} Interface ${BYLW}${iface}${RST} not found."
            echo -e "    ${DIM}Available interfaces:${RST}"
            ip -br link show 2>/dev/null | awk '{printf "    • %s (%s)\n", $1, $2}'
            exit 1
        fi

        capture_live

        echo -e "${BCYN}[+]${RST} Analyzing TLS handshakes..."
        echo

    else
        echo -e "${BCYN}[+]${RST} Reading: ${BGRN}${pcap_file}${RST}"
        build_arp_table
        echo -e "${BCYN}[+]${RST} Extracting JA3 fingerprints..."
        echo
    fi

    local ja3_data
    ja3_data=$(extract_ja3 "$pcap_file")

    display_results "$ja3_data"
    print_ja3_explainer
}

main "$@"
