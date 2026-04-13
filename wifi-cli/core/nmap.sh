#!/bin/bash

# Get the subnet of the selected interface (e.g., 192.168.1.0/24)
_get_subnet() {
    ip -o -f inet addr show "$iface" 2>/dev/null \
        | awk '{print $4}' \
        | head -n1
}

# Discover live hosts on the interface's subnet
host_discovery() {
    if [[ -z "$iface" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Select an interface first!"
        pause
        return
    fi

    local subnet
    subnet=$(_get_subnet)

    if [[ -z "$subnet" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Could not determine subnet for ${BOLD_GREEN}${iface}${NC}."
        pause
        return
    fi

    clear
    echo -e "${BOLD_CYAN}[+]${NC} Running host discovery on ${BOLD_GREEN}${subnet}${NC}..."
    echo

    # -sn = ping scan (no port scan), -T4 = faster timing
    nmap_hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
        | awk '/Nmap scan report/{ip=$NF} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$nmap_hosts" ]]; then
        echo -e "${BOLD_YELLOW}[!]${NC} No hosts found. Make sure ${BOLD_GREEN}${iface}${NC} has an IP on this subnet."
        pause
        return
    fi

    echo -e "${BOLD_CYAN}Live Hosts:${NC}"
    echo
    echo "$nmap_hosts" | nl -w2 -s') '
    pause
}

# Port scan a host selected from the discovery list
port_scan() {
    if [[ -z "$iface" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Select an interface first!"
        pause
        return
    fi

    local subnet
    subnet=$(_get_subnet)

    if [[ -z "$subnet" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Could not determine subnet for ${BOLD_GREEN}${iface}${NC}."
        pause
        return
    fi

    # Refresh host list silently
    local hosts
    hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
        | awk '/Nmap scan report/{ip=$NF} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$hosts" ]]; then
        echo -e "${BOLD_YELLOW}[!]${NC} No hosts found. Run host discovery first."
        pause
        return
    fi

    clear
    echo -e "${BOLD_CYAN}Select host to port scan:${NC}"
    echo
    echo "$hosts" | nl -w2 -s') '
    echo
    read -p "  Host number: " num

    local target_ip
    target_ip=$(echo "$hosts" | sed -n "${num}p" | awk '{print $1}')

    if [[ -z "$target_ip" ]]; then
        echo -e "${BOLD_RED}[!]${NC} Invalid selection."
        pause
        return
    fi

    clear
    echo -e "${BOLD_CYAN}[+]${NC} Port scanning ${BOLD_GREEN}${target_ip}${NC}..."
    echo

    # -sV = service/version detection, -T4 = fast, --open = show only open ports
    nmap -sV -T4 --open "$target_ip"

    pause
}
