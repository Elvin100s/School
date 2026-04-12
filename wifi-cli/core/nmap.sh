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
        echo "Select an interface first!"
        pause
        return
    fi

    local subnet
    subnet=$(_get_subnet)

    if [[ -z "$subnet" ]]; then
        echo "Could not determine subnet for $iface."
        pause
        return
    fi

    clear
    echo "[+] Running host discovery on $subnet ..."
    echo

    # -sn = ping scan (no port scan), -T4 = faster timing
    nmap_hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
        | awk '/Nmap scan report/{ip=$NF} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$nmap_hosts" ]]; then
        echo "No hosts found. Make sure $iface has an IP on this subnet."
        pause
        return
    fi

    echo "Live Hosts:"
    echo
    echo "$nmap_hosts" | nl -w2 -s') '
    pause
}

# Port scan a host selected from the discovery list
port_scan() {
    if [[ -z "$iface" ]]; then
        echo "Select an interface first!"
        pause
        return
    fi

    local subnet
    subnet=$(_get_subnet)

    if [[ -z "$subnet" ]]; then
        echo "Could not determine subnet for $iface."
        pause
        return
    fi

    # Refresh host list silently
    local hosts
    hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
        | awk '/Nmap scan report/{ip=$NF} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$hosts" ]]; then
        echo "No hosts found. Run host discovery first."
        pause
        return
    fi

    clear
    echo "Select host to port scan:"
    echo
    echo "$hosts" | nl -w2 -s') '
    echo
    read -p "Host number: " num

    local target_ip
    target_ip=$(echo "$hosts" | sed -n "${num}p" | awk '{print $1}')

    if [[ -z "$target_ip" ]]; then
        echo "Invalid selection."
        pause
        return
    fi

    clear
    echo "[+] Port scanning $target_ip ..."
    echo

    # -sV = service/version detection, -T4 = fast, --open = show only open ports
    nmap -sV -T4 --open "$target_ip"

    pause
}
