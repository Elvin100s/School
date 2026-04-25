#!/bin/bash
# setup.sh — Pre-flight dependency installer and hardware auditor for wifi-cli

# Source UI components
if [[ -f "utils/ui.sh" ]]; then
    source utils/ui.sh
else
    echo "Error: utils/ui.sh not found. Run this from the project root."
    exit 1
fi

# Packages needed
PACKAGES=(aircrack-ng nmap tcpdump net-tools iw network-manager macchanger dsniff iproute2 hostapd dnsmasq python3 iptables)

check_deps() {
    echo -e "${BOLD_CYAN}[+] Checking system dependencies...${NC}"
    local missing=()
    for pkg in "${PACKAGES[@]}"; do
        # Map package names to their primary command counterparts for checking
        local cmd=$pkg
        [[ "$pkg" == "aircrack-ng" ]] && cmd="airmon-ng"
        [[ "$pkg" == "net-tools" ]] && cmd="arp"
        [[ "$pkg" == "network-manager" ]] && cmd="nmcli"
        [[ "$pkg" == "iproute2" ]] && cmd="tc"
        [[ "$pkg" == "dsniff" ]] && cmd="arpspoof"

        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${BOLD_YELLOW}[!] Missing packages: ${BOLD_WHITE}${missing[*]}${NC}"
        echo
        read -p "    Would you like to install them now? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BOLD_CYAN}[+] Updating package lists...${NC}"
            apt update
            echo -e "${BOLD_CYAN}[+] Installing missing tools...${NC}"
            apt install "${missing[@]}" -y
            if [ $? -eq 0 ]; then
                echo -e "${BOLD_GREEN}[+] Dependencies installed successfully.${NC}"
            else
                echo -e "${BOLD_RED}[!] Installation failed. Please check your internet connection and try again.${NC}"
                exit 1
            fi
        else
            echo -e "${BOLD_RED}[!] Cannot continue without required dependencies.${NC}"
            exit 1
        fi
    else
        echo -e "${BOLD_GREEN}[+] All software dependencies are met.${NC}"
    fi
}

check_adapter() {
    echo
    echo -e "${BOLD_CYAN}[+] Auditing wireless hardware...${NC}"
    
    # Get all wireless interfaces
    local interfaces=($(iw dev | awk '$1=="Interface"{print $2}'))

    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${BOLD_RED}[!] No wireless adapters detected.${NC}"
        echo -e "    ${DIM}Ensure your WiFi adapter is plugged in and drivers are loaded.${NC}"
        echo -e "    ${DIM}Common command to check: 'lspci' or 'lsusb'${NC}"
        exit 1
    fi

    echo -e "${BOLD_GREEN}[+] Found ${#interfaces[@]} wireless interface(s): ${BOLD_WHITE}${interfaces[*]}${NC}"
    echo

    local compatible=0
    for iface in "${interfaces[@]}"; do
        echo -e "    - Analyzing ${BOLD_CYAN}${iface}${NC}..."
        
        # Get the wiphy index (phy0, phy1, etc)
        local phy_idx=$(iw dev "$iface" info | awk '/wiphy/ {print $2}')
        local phy="phy${phy_idx}"
        
        # Check for monitor mode support
        if iw phy "$phy" info 2>/dev/null | grep -q "monitor"; then
            echo -e "      ${BOLD_GREEN}✔ Supports Monitor Mode${NC}"
            ((compatible++))
        else
            echo -e "      ${BOLD_RED}✘ Monitor Mode not supported by hardware/driver${NC}"
        fi

        # Check for 5 GHz band support
        if iw phy "$phy" info 2>/dev/null | grep -q "5[0-9][0-9][0-9] MHz"; then
            echo -e "      ${BOLD_GREEN}✔ Dual-band (2.4 GHz + 5 GHz)${NC}"
        else
            echo -e "      ${BOLD_YELLOW}~ 2.4 GHz only — 5 GHz scan options will be hidden${NC}"
        fi
    done

    echo
    if [ $compatible -gt 0 ]; then
        echo -e "${BOLD_GREEN}[+] Hardware check passed. You have at least one compatible adapter.${NC}"
    else
        echo -e "${BOLD_YELLOW}[!] Warning: None of your detected adapters appear to support Monitor Mode.${NC}"
        echo -e "    ${DIM}The framework may have limited functionality (e.g., only Nmap and Throttle).${NC}"
    fi
}

main() {
    clear
    print_banner
    echo -e "  ${BOLD_CYAN}Pre-flight Setup & Hardware Audit${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────${NC}"
    echo

    # Must be root
    check_root

    # Run checks
    check_deps
    check_adapter

    echo
    echo -e "${BOLD_GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD_GREEN}║  SETUP COMPLETE! You are ready to run wifi-cli   ║${NC}"
    echo -e "${BOLD_GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  To start the framework, run:"
    echo -e "  ${BOLD_CYAN}sudo ./wifi-cli.sh${NC}"
    echo
}

main
