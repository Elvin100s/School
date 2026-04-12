#!/bin/bash
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
        echo -e "\n[+] Cleaning up monitor mode..."
        airmon-ng stop "$mon_iface" 2>/dev/null
        systemctl start NetworkManager 2>/dev/null
        sleep 2
        if [[ -n "$saved_conn" ]]; then
            nmcli connection up "$saved_conn" 2>/dev/null
        fi
    fi
    echo "[+] WiFi restored. Exiting."
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
    echo -e "${BOLD_CYAN}========== WiFi CLI Framework ==========${NC}"
    echo
    echo -e "${DIM}Interface :${NC} ${iface:+${GREEN}${iface}${NC}}${iface:-${YELLOW}Not set${NC}}"

    # Show current Wi-Fi connection only if interface is selected & in managed mode
    if [[ -n "$iface" && -z "$mon_iface" ]]; then
        show_current_conn "$iface"
    fi

    echo -e "${DIM}Monitor   :${NC} ${mon_iface:+${GREEN}${mon_iface}${NC}}${mon_iface:-${YELLOW}Not set${NC}}"
    echo -e "${DIM}Target    :${NC} ${bssid:+${GREEN}${bssid}${NC}}${bssid:-${YELLOW}Not set${NC}}"
    echo -e "${DIM}Channel   :${NC} ${channel:+${GREEN}${channel}${NC}}${channel:-${YELLOW}Not set${NC}}"
    echo
    echo -e "  ${CYAN}1)${NC} Quick Wizard"
    echo -e "  ${CYAN}2)${NC} Manual Mode"
    echo
    echo -e "${DIM}-- Network Recon --${NC}"
    echo -e "  ${CYAN}3)${NC} Host Discovery (nmap)"
    echo -e "  ${CYAN}4)${NC} Port Scan Host (nmap)"
    echo
    echo -e "  ${YELLOW}5)${NC} Exit"
    echo
    read -p "Choice: " choice
    case $choice in
        1) quick_wizard ;;
        2) manual_menu ;;
        3) host_discovery ;;
        4) port_scan ;;
        5) exit 0 ;;
        *) echo -e "${RED}Invalid choice${NC}" ; sleep 1 ;;
    esac
done