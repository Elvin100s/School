#!/bin/bash

ensure_monitor() {
    if [[ -z "$iface" ]]; then
        echo -e "${BOLD_YELLOW}[*]${NC} No interface selected — launching interface selection..."
        sleep 1
        select_interface
    fi
    if [[ -z "$iface" ]]; then
        return 1
    fi
    if [[ -z "$mon_iface" ]]; then
        echo -e "${BOLD_YELLOW}[*]${NC} Monitor mode not active — enabling now..."
        sleep 1
        enable_monitor
    fi
    if [[ -z "$mon_iface" ]]; then
        return 1
    fi
    return 0
}

enable_monitor() {

if [[ -z "$iface" ]]; then
echo -e "${BOLD_RED}[!]${NC} Select interface first!"
pause
return
fi

if iw dev "$iface" info 2>/dev/null | grep -q "type monitor"; then
echo -e "${BOLD_YELLOW}[!]${NC} ${BOLD_GREEN}${iface}${NC} is already in monitor mode!"
pause
return
fi

clear

# Save current connection profile before killing processes
saved_conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1)

# Spoof MAC before going into monitor mode
if command -v macchanger &>/dev/null; then
    echo -e "${BOLD_CYAN}[+]${NC} Spoofing MAC address..."
    ip link set "$iface" down 2>/dev/null
    local spoofed_mac
    spoofed_mac=$(macchanger -r "$iface" 2>/dev/null | awk '/New MAC/{print $3}')
    ip link set "$iface" up 2>/dev/null
    if [[ -n "$spoofed_mac" ]]; then
        echo -e "${BOLD_GREEN}[+]${NC} MAC spoofed to ${BOLD_GREEN}${spoofed_mac}${NC}"
    else
        echo -e "${BOLD_YELLOW}[!]${NC} MAC spoof failed — continuing anyway"
    fi
    echo
else
    echo -e "${BOLD_YELLOW}[!]${NC} macchanger not found — skipping MAC spoof"
    echo -e "    ${DIM}Install with: apt install macchanger${NC}"
    echo
fi

echo -e "${BOLD_CYAN}[+]${NC} Killing interfering processes..."
echo

airmon-ng check kill

echo
echo -e "${BOLD_CYAN}[+]${NC} Enabling monitor mode on ${BOLD_GREEN}${iface}${NC}"
echo

airmon-ng start "$iface"

sleep 2

# detect monitor interface
mon_iface=$(iw dev | awk '$1=="Interface"{print $2}' | grep -E "mon|$iface" | head -n 1)

if [[ -z "$mon_iface" ]]; then
echo
echo -e "${BOLD_RED}[!]${NC} Monitor mode failed!"
pause
return
fi

echo
echo -e "${BOLD_GREEN}[+]${NC} Monitor interface: ${BOLD_GREEN}${mon_iface}${NC}"
pause
}

stop_monitor() {

if [[ -z "$mon_iface" ]]; then
echo -e "${BOLD_RED}[!]${NC} No monitor interface active!"
pause
return
fi

clear
echo -e "${BOLD_CYAN}[+]${NC} Stopping monitor mode..."
echo

airmon-ng stop "$mon_iface"

echo
echo -e "${BOLD_CYAN}[+]${NC} Restoring NetworkManager..."
systemctl start NetworkManager
sleep 2
if [[ -n "$saved_conn" ]]; then
    echo -e "${BOLD_CYAN}[+]${NC} Reconnecting to ${BOLD_GREEN}${saved_conn}${NC}..."
    nmcli connection up "$saved_conn" 2>/dev/null
fi

# reset variable
mon_iface=""