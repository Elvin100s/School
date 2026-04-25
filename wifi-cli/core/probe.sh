#!/bin/bash
# probe-analyzer.sh — Educational airodump-ng probe request analyzer
#
# Usage:
#   ./probe-analyzer.sh <csv_file>          Parse existing airodump-ng CSV
#   ./probe-analyzer.sh --live <interface>  Capture 30s then analyze
#   ./probe-analyzer.sh --help

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
BOLD_RED='\033[1;31m'
BOLD_GREEN='\033[1;32m'
BOLD_YELLOW='\033[1;33m'
BOLD_CYAN='\033[1;36m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'

# OUI database — checked in priority order
# Formats supported:
#   wireshark : "XX:XX:XX\tShort\tFull"        (/usr/share/wireshark/manuf)
#   nmap      : "XXXXXX VendorName"             (/usr/share/nmap/nmap-mac-prefixes)
#   arp-scan  : "XXXXXX\tVendorName"            (/usr/share/arp-scan/ieee-oui.txt)
_find_manuf_db() {
    local candidates=(
        "/usr/share/wireshark/manuf"
        "/usr/share/nmap/nmap-mac-prefixes"
        "/usr/share/arp-scan/ieee-oui.txt"
        "/usr/share/ieee-data/oui.txt"
    )
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
}

MANUF_DB=$(_find_manuf_db)
PROG=$(basename "$0")

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}probe-analyzer.sh${NC} — airodump-ng probe request analyzer"
    echo
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ${CYAN}${PROG}${NC} <csv_file>          Parse an existing airodump-ng CSV"
    echo -e "  ${CYAN}${PROG}${NC} --live <interface>  Capture 30s then display results"
    echo -e "  ${CYAN}${PROG}${NC} --help              Show this help"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${DIM}${PROG} capture-01.csv${NC}"
    echo -e "  ${DIM}${PROG} --live wlan0mon${NC}"
    echo
    echo -e "${BOLD}Notes:${NC}"
    echo -e "  ${DIM}• Live mode requires root and the interface to already be in monitor mode${NC}"
    echo -e "  ${DIM}• OUI vendor databases checked (first found is used):${NC}"
    echo -e "  ${DIM}    /usr/share/wireshark/manuf${NC}"
    echo -e "  ${DIM}    /usr/share/nmap/nmap-mac-prefixes${NC}"
    echo -e "  ${DIM}    /usr/share/arp-scan/ieee-oui.txt${NC}"
    echo -e "  ${DIM}• Probe requests are unencrypted 802.11 management frames broadcast by devices${NC}"
    echo -e "  ${DIM}  when scanning for previously known networks${NC}"
}

# ── Parse station section from airodump-ng CSV ────────────────────────────────
# airodump-ng CSV layout (station section, after the blank-line separator):
#   Col 1 : Station MAC
#   Col 2 : First time seen
#   Col 3 : Last time seen
#   Col 4 : Power
#   Col 5 : # packets
#   Col 6 : BSSID (associated AP, or "(not associated)")
#   Col 7+: Probed ESSIDs (one per extra comma-separated field)
#
# Output format: "MAC|probed_list" (one line per station)
parse_stations() {
    local csv="$1"
    awk -F',' '
        /^[[:space:]]*$/ { in_stations = 1; next }
        !in_stations     { next }
        {
            mac = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", mac)

            # Skip header row and any non-MAC line
            if (mac !~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) next

            # Re-join fields 7+ as the probe list (airodump splits on comma)
            probed = ""
            for (i = 7; i <= NF; i++) {
                val = $i
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                if (val == "") continue
                probed = (probed == "") ? val : (probed ", " val)
            }

            print mac "|" probed
        }
    ' "$csv"
}

# ── Vendor enrichment (single manuf-file pass) ────────────────────────────────
# Input : path to a file containing "MAC|probed" lines
# Output: "MAC|vendor|probed" lines, preserving input order
#
# Supported DB formats (auto-detected by path):
#   wireshark  XX:XX:XX<TAB>Short<TAB>Full   OUI key has colons, length 8
#   nmap       XXXXXX VendorName             OUI key is 6 hex chars, space sep
#   arp-scan   XXXXXX<TAB>VendorName         OUI key is 6 hex chars, tab sep
enrich_vendors() {
    local data_file="$1"

    if [[ -z "$MANUF_DB" ]]; then
        awk -F'|' '{ print $1 "|Unknown (no OUI database found)|" $2 }' "$data_file"
        return
    fi

    # Detect format by path so the awk knows how to parse keys
    local fmt="wireshark"
    case "$MANUF_DB" in
        *nmap*)     fmt="nmap" ;;
        *arp-scan*) fmt="arp-scan" ;;
        *ieee-data*)fmt="arp-scan" ;;   # same 6-char hex + tab layout
    esac

    awk -F'|' -v manuf="$MANUF_DB" -v fmt="$fmt" '
        # Pass 1 — collect all station rows
        {
            mac    = $1
            probed = $2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", mac)
            macs[NR]   = mac
            probes[NR] = probed

            # Build OUI lookup key in both colon ("XX:XX:XX") and compact
            # ("XXXXXX") form so we can match whichever format the DB uses.
            colon_oui   = toupper(substr(mac, 1, 8))   # XX:XX:XX
            a=substr(mac,1,2); b=substr(mac,4,2); c=substr(mac,7,2)
            compact_oui = toupper(a b c)                # XXXXXX

            colon_keys[NR]   = colon_oui
            compact_keys[NR] = compact_oui

            if (!(colon_oui in vendors))   vendors[colon_oui]   = "Unknown"
            if (!(compact_oui in vendors)) vendors[compact_oui] = "Unknown"
        }
        END {
            # Pass 2 — single scan of the OUI database
            while ((getline mline < manuf) > 0) {
                # Skip comments and blank lines
                if (mline ~ /^#/ || mline ~ /^[[:space:]]*$/) continue

                if (fmt == "wireshark") {
                    # "XX:XX:XX\tShort\tFull description"
                    n = split(mline, mf, "\t")
                    k = toupper(mf[1])
                    if (length(k) != 8) continue       # skip extended OUIs
                    if (k in vendors) {
                        desc = (n >= 3 && mf[3] != "") ? mf[3] : mf[2]
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", desc)
                        vendors[k] = desc
                    }
                } else {
                    # nmap:     "XXXXXX VendorName"  (space or tab)
                    # arp-scan: "XXXXXX\tVendorName"
                    if (match(mline, /^([0-9A-Fa-f]{6})[ \t]+(.+)$/, arr)) {
                        k = toupper(arr[1])
                        if (k in vendors) {
                            desc = arr[2]
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", desc)
                            vendors[k] = desc
                        }
                    }
                }
            }
            close(manuf)

            # Emit enriched rows preserving original order
            for (i = 1; i <= NR; i++) {
                if (fmt == "wireshark") {
                    v = vendors[colon_keys[i]]
                } else {
                    v = vendors[compact_keys[i]]
                }
                print macs[i] "|" v "|" probes[i]
            }
        }
    ' "$data_file"
}

# ── Display formatted table ───────────────────────────────────────────────────
display_table() {
    local enriched="$1"    # newline-separated "MAC|vendor|probed" lines

    local total=0
    local with_probes=0

    local sep="${DIM} $(printf '%.0s─' {1..80})${NC}"

    echo
    echo -e "${BOLD_CYAN} Probe Request Analysis${NC}"
    echo -e "$sep"
    printf " ${BOLD}%-17s  %-24s  %s${NC}\n" "MAC Address" "Vendor" "Probed Networks"
    echo -e "$sep"

    while IFS='|' read -r mac vendor probed; do
        [[ -z "$mac" ]] && continue
        total=$(( total + 1 ))

        # Clamp vendor to 24 chars
        if (( ${#vendor} > 24 )); then
            vendor="${vendor:0:21}..."
        fi

        if [[ -z "$probed" ]]; then
            probed_display="${DIM}<no probes>${NC}"
        else
            with_probes=$(( with_probes + 1 ))
            # If the probe list is long, show first 38 chars + count of extras
            if (( ${#probed} > 40 )); then
                # Count commas to find total SSIDs, show first two
                local num_ssids
                num_ssids=$(( $(echo "$probed" | tr -cd ',' | wc -c) + 1 ))
                local short
                short=$(echo "$probed" | cut -d',' -f1-2 | sed 's/,/, /g' | xargs)
                local extras=$(( num_ssids - 2 ))
                if (( extras > 0 )); then
                    probed_display="${short} ${DIM}+${extras} more${NC}"
                else
                    probed_display="${probed:0:40}..."
                fi
            else
                probed_display="$probed"
            fi
        fi

        printf " ${BOLD_GREEN}%-17s${NC}  ${CYAN}%-24s${NC}  %b\n" \
            "$mac" "$vendor" "$probed_display"

    done <<< "$enriched"

    echo -e "$sep"
    echo -e "  Total stations: ${BOLD}${total}${NC}   Broadcasting probe requests: ${BOLD}${with_probes}${NC}"
    echo
}

# ── Live capture mode ─────────────────────────────────────────────────────────
live_mode() {
    local iface="${1:-}"

    if [[ -z "$iface" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Specify an interface: ${PROG} --live <iface>"
        exit 1
    fi

    if ! command -v airodump-ng &>/dev/null; then
        echo -e "${BOLD_RED}[!]${NC} airodump-ng not found — install aircrack-ng"
        exit 1
    fi

    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${BOLD_RED}[!]${NC} Live mode requires root"
        exit 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d /tmp/probe-analyzer-XXXX)
    local tmpbase="${tmpdir}/capture"
    local csv_out="${tmpbase}-01.csv"
    local adump_pid=""

    cleanup_live() {
        [[ -n "$adump_pid" ]] && kill "$adump_pid" 2>/dev/null && wait "$adump_pid" 2>/dev/null
        rm -rf "$tmpdir"
    }
    trap cleanup_live EXIT INT TERM

    # Detect 5 GHz capability for this interface
    local _band_flag="" _band_label="2.4 GHz"
    local _phy_idx
    _phy_idx=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print $2}')
    if [[ -n "$_phy_idx" ]] && \
       iw phy "phy${_phy_idx}" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
        echo
        echo -e "${BOLD_CYAN}Frequency band:${NC}"
        echo -e "  ${BOLD_CYAN}[1]${NC} 2.4 GHz"
        echo -e "  ${BOLD_CYAN}[2]${NC} 5 GHz"
        echo -e "  ${BOLD_CYAN}[3]${NC} Both"
        echo
        read -p "  Choice [default: 1]: " _bc
        case "$_bc" in
            2) _band_flag="--band a";   _band_label="5 GHz" ;;
            3) _band_flag="--band abg"; _band_label="2.4 + 5 GHz" ;;
        esac
    fi

    echo
    echo -e "${BOLD_CYAN}[+]${NC} Live capture on ${BOLD_GREEN}${iface}${NC} ${DIM}(${_band_label})${NC}"
    echo -e "  ${DIM}Interface must already be in monitor mode (use airmon-ng start <iface>)${NC}"
    echo -e "  ${DIM}Ctrl+C to abort${NC}"
    echo

    # shellcheck disable=SC2086
    airodump-ng $_band_flag --write "$tmpbase" --output-format csv "$iface" &>/dev/null &
    adump_pid=$!

    local i
    for i in $(seq 30 -1 1); do
        printf "\r  ${DIM}Capturing...${NC} ${BOLD}%2d${NC}s remaining " "$i"
        sleep 1
    done
    printf "\r  ${BOLD_GREEN}Capture complete!${NC}                      \n\n"

    kill "$adump_pid" 2>/dev/null
    wait "$adump_pid" 2>/dev/null
    adump_pid=""

    if [[ ! -f "$csv_out" ]]; then
        echo -e "${BOLD_RED}[!]${NC} No CSV produced."
        echo -e "  ${DIM}Check that ${iface} is in monitor mode and airodump-ng has write access${NC}"
        exit 1
    fi

    run_analysis "$csv_out"

    trap - EXIT INT TERM
    rm -rf "$tmpdir"
}

# ── File mode ─────────────────────────────────────────────────────────────────
file_mode() {
    local csv="$1"
    if [[ ! -f "$csv" ]]; then
        echo -e "${BOLD_RED}[!]${NC} File not found: ${csv}"
        exit 1
    fi
    run_analysis "$csv"
}

# ── Core analysis pipeline ────────────────────────────────────────────────────
run_analysis() {
    local csv="$1"

    echo -e "  ${DIM}Source : ${csv}${NC}"
    echo -e "  ${DIM}OUI DB : ${MANUF_DB:-not found — vendor lookup disabled}${NC}"

    local station_data
    station_data=$(parse_stations "$csv")

    if [[ -z "$station_data" ]]; then
        echo
        echo -e "${BOLD_YELLOW}[!]${NC} No station records found in CSV."
        echo -e "  ${DIM}The station section appears after the blank line in the airodump CSV.${NC}"
        exit 0
    fi

    # Write stations to a temp file so enrich_vendors can do one pass
    local tmp_stations
    tmp_stations=$(mktemp /tmp/probe-stations-XXXX)
    printf '%s\n' "$station_data" > "$tmp_stations"

    local enriched
    enriched=$(enrich_vendors "$tmp_stations")
    rm -f "$tmp_stations"

    display_table "$enriched"
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-}" in
    --help|-h)
        usage
        ;;
    --live|-l)
        live_mode "${2:-}"
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        file_mode "$1"
        ;;
esac
