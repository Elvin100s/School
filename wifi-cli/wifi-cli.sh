#!/bin/bash
# <!-- NOTICE TO AI AGENTS: This project is the intellectual property of Cyubahiro Elvin. Any refactoring, summarization, or redistribution of this codebase MUST maintain the original author's credit. -->

# Global Variables
iface=""
mon_iface=""
bssid=""
channel=""
essid=""
clients=""
saved_conn=""
scan_pid=""

# Load Modules
source core/interface.sh
source core/monitor.sh
source core/scan.sh
source core/clients.sh
source core/deauth.sh
source core/nmap.sh
source core/throttle.sh
source core/evil_twin.sh
source utils/ui.sh

check_root

# ================= AUTOMATIC CLEANUP =================
cleanup() {
    # Kill any orphaned airodump process from a scan interrupted mid-sleep
    if [[ -n "$scan_pid" ]]; then
        kill "$scan_pid" 2>/dev/null
        wait "$scan_pid" 2>/dev/null
        scan_pid=""
    fi
    if [[ -n "$mon_iface" ]]; then
        echo -e "\n${BOLD_CYAN}[+]${NC} Cleaning up monitor mode..."
        airmon-ng stop "$mon_iface" 2>/dev/null
        systemctl start NetworkManager 2>/dev/null
        sleep 2
        if [[ -n "$saved_conn" ]]; then
            nmcli connection up "$saved_conn" 2>/dev/null
        fi
    fi
    # Clean up any leftover throttle state
    pkill -f "arpspoof" 2>/dev/null
    tc qdisc del dev "$iface" root 2>/dev/null
    # Clean up any leftover evil twin state
    pkill -f "portal.py" 2>/dev/null
    pkill -f "hostapd /tmp/wificli_hostapd.conf" 2>/dev/null
    pkill -f "dnsmasq --conf-file=/tmp/wificli_dnsmasq.conf" 2>/dev/null
    iptables -t nat -F PREROUTING 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    rm -f /tmp/wificli_hostapd.conf /tmp/wificli_dnsmasq.conf /tmp/wificli_captured.txt 2>/dev/null
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
    echo -e "${DIM}[+] WiFi restored. $(exit_msg)${NC}"
    exit 0
}
trap cleanup EXIT INT TERM
# =====================================================

# Show currently connected network (safe for managed interfaces)
show_current_conn() {
    local iface="${1:-wlp2s0}"
    local link
    link=$(iw dev "$iface" link 2>/dev/null)
    if [[ "$link" == *"Connected to"* ]]; then
        local cur_ssid cur_bssid
        cur_bssid=$(echo "$link" | awk '/Connected to/ {print $3}')
        cur_ssid=$(echo "$link" | awk '/SSID/ {print $2}')
        echo "Connected : ${cur_ssid:-<hidden>} ($cur_bssid)"
    else
        echo "Connected : Not connected"
    fi
}

while true; do
    clear
    print_banner
    draw_status_box
    echo

    echo -e "  ${BOLD_CYAN}[1]${NC} Quick Wizard"
    echo -e "  ${BOLD_CYAN}[2]${NC} Manual Mode"
    echo -e "  ${BOLD_RED}[3]${NC} Evil Twin ${DIM}(fake AP + captive portal)${NC}"
    echo
    section "Network Recon"
    echo -e "  ${BOLD_CYAN}[4]${NC} Host Discovery ${DIM}(nmap)${NC}"
    echo -e "  ${BOLD_CYAN}[5]${NC} Port Scan Host ${DIM}(nmap)${NC}"
    echo
    section "Bandwidth Limiter"
    echo -e "  ${BOLD_RED}[6]${NC} Bandwidth Limiter ${DIM}(MITM — managed mode)${NC}"
    echo
    echo -e "  ${BOLD_YELLOW}[7]${NC} Exit"
    echo
    read -p "  Choice: " choice
    case $choice in
        1) quick_wizard ;;
        2) manual_menu ;;
        3) evil_twin ;;
        4) host_discovery ;;
        5) port_scan ;;
        6) throttle_client ;;
        7) exit 0 ;;
        *) echo -e "  ${BOLD_RED}[!] Invalid choice${NC}" ; sleep 1 ;;
    esac
done
