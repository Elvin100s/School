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
        select_interface
        [[ -z "$iface" ]] && return
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
        | awk '/Nmap scan report/{ip=$NF; gsub(/[()]/, "", ip)} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$nmap_hosts" ]]; then
        echo -e "${BOLD_YELLOW}[!]${NC} No hosts found. Make sure ${BOLD_GREEN}${iface}${NC} has an IP on this subnet."
        pause
        return
    fi

    echo -e "${BOLD_CYAN}Live Hosts:${NC}"
    echo
    local _n=1
    while IFS=' ' read -r _ip _mac; do
        printf "  ${BOLD_CYAN}%2d)${NC}  ${GREEN}%-16s${NC}  ${BOLD_MAGENTA}%s${NC}\n" "$_n" "$_ip" "$_mac"
        (( _n++ )) || true
    done <<< "$nmap_hosts"
    pause
}

# Port scan a host selected from the discovery list
port_scan() {
    if [[ -z "$iface" ]]; then
        select_interface
        [[ -z "$iface" ]] && return
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
        | awk '/Nmap scan report/{ip=$NF; gsub(/[()]/, "", ip)} /MAC Address/{mac=$3; print ip, mac}')

    if [[ -z "$hosts" ]]; then
        echo -e "${BOLD_YELLOW}[!]${NC} No hosts found. Run host discovery first."
        pause
        return
    fi

    clear
    echo -e "${BOLD_CYAN}Select host to port scan:${NC}"
    echo
    local _n=1
    while IFS=' ' read -r _ip _mac; do
        printf "  ${BOLD_CYAN}%2d)${NC}  ${GREEN}%-16s${NC}  ${BOLD_MAGENTA}%s${NC}\n" "$_n" "$_ip" "$_mac"
        (( _n++ )) || true
    done <<< "$hosts"
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

# Web vulnerability scan using Nikto
web_scan() {
    if ! command -v nikto &>/dev/null; then
        echo -e "${BOLD_RED}[!]${NC} nikto not found."
        echo -e "    ${DIM}Install with: apt install nikto${NC}"
        pause
        return
    fi

    clear
    echo -e "${BOLD_CYAN}========== Web Vulnerability Scan ==========${NC}"
    echo
    echo -e "${BOLD_CYAN}Target:${NC}"
    echo -e "  ${BOLD_CYAN}[1]${NC} Scan network and pick a host"
    echo -e "  ${BOLD_CYAN}[2]${NC} Enter IP / URL manually"
    echo
    read -p "  Choice [default: 1]: " target_mode
    echo

    local target_ip
    if [[ "$target_mode" == "2" ]]; then
        read -p "  Enter IP or URL: " target_ip
        if [[ -z "$target_ip" ]]; then
            echo -e "${BOLD_RED}[!]${NC} No target entered."
            pause; return
        fi
    else
        if [[ -z "$iface" ]]; then
            select_interface
            [[ -z "$iface" ]] && return
        fi

        local subnet
        subnet=$(_get_subnet)

        if [[ -z "$subnet" ]]; then
            echo -e "${BOLD_RED}[!]${NC} No IP on ${BOLD_GREEN}${iface}${NC} — connect to a network first."
            pause; return
        fi

        echo -e "${BOLD_CYAN}[+]${NC} Scanning for hosts on ${BOLD_GREEN}${subnet}${NC}..."
        echo
        local hosts
        hosts=$(nmap -sn -T4 "$subnet" 2>/dev/null \
            | awk '/Nmap scan report/{ip=$NF; gsub(/[()]/, "", ip)} /MAC Address/{mac=$3; print ip, mac}')

        if [[ -z "$hosts" ]]; then
            echo -e "${BOLD_YELLOW}[!]${NC} No hosts found."
            pause; return
        fi

        local _n=1
        while IFS=' ' read -r _ip _mac; do
            printf "  ${BOLD_CYAN}%2d)${NC}  ${GREEN}%-16s${NC}  ${BOLD_MAGENTA}%s${NC}\n" "$_n" "$_ip" "$_mac"
            (( _n++ )) || true
        done <<< "$hosts"
        echo
        read -p "  Host number: " num

        target_ip=$(echo "$hosts" | sed -n "${num}p" | awk '{print $1}')
        if [[ -z "$target_ip" ]]; then
            echo -e "${BOLD_RED}[!]${NC} Invalid selection."
            pause; return
        fi
    fi

    echo
    echo -e "${BOLD_CYAN}Target port:${NC}"
    echo -e "  ${BOLD_CYAN}[1]${NC} HTTP   ${DIM}(port 80)${NC}"
    echo -e "  ${BOLD_CYAN}[2]${NC} HTTPS  ${DIM}(port 443)${NC}"
    echo -e "  ${BOLD_CYAN}[3]${NC} Both   ${DIM}(80 + 443)${NC}"
    echo -e "  ${BOLD_CYAN}[4]${NC} Custom"
    echo
    read -p "  Choice [default: 1]: " port_choice

    local nikto_port nikto_ssl=""
    case "$port_choice" in
        2) nikto_port="443"; nikto_ssl="-ssl" ;;
        3) nikto_port="80,443" ;;
        4)
            read -p "  Port: " nikto_port
            if ! [[ "$nikto_port" =~ ^[0-9]+$ ]]; then
                echo -e "${BOLD_RED}[!]${NC} Invalid port."
                pause; return
            fi
            ;;
        *) nikto_port="80" ;;
    esac

    # ── Gobuster option ───────────────────────────────────────────────────
    local _run_gobuster=false _wordlist=""
    if command -v gobuster &>/dev/null; then
        for _wl in \
            /usr/share/wordlists/dirb/common.txt \
            /usr/share/wordlists/dirbuster/directory-list-2.3-small.txt \
            /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt; do
            [[ -f "$_wl" ]] && _wordlist="$_wl" && break
        done
        if [[ -n "$_wordlist" ]]; then
            echo
            read -p "  Also run Gobuster on found paths after Nikto? [y/N] " _gb_choice
            [[ "$_gb_choice" =~ ^[Yy]$ ]] && _run_gobuster=true
        fi
    fi

    # Output files
    local _safe_target
    _safe_target=$(echo "$target_ip" | tr -cd '[:alnum:]._-')
    local _ts; _ts=$(date +%H%M%S)
    local outfile="/tmp/wificli_nikto_${_safe_target}_${_ts}.txt"
    local gb_outfile="/tmp/wificli_gobuster_${_safe_target}_${_ts}.txt"

    clear
    echo -e "${BOLD_CYAN}========== Web Vulnerability Scan ==========${NC}"
    echo -e "  ${DIM}Target  :${NC} ${BOLD_GREEN}${target_ip}${NC}"
    echo -e "  ${DIM}Port    :${NC} ${BOLD_GREEN}${nikto_port}${NC}"
    $_run_gobuster && echo -e "  ${DIM}Gobuster:${NC} ${BOLD_GREEN}enabled${NC} ${DIM}(${_wordlist##*/})${NC}"
    echo -e "  ${DIM}Saving  :${NC} ${DIM}${outfile}${NC}"
    echo

    # ── Run Nikto ─────────────────────────────────────────────────────────
    echo -e "${BOLD_CYAN}── Nikto ────────────────────────────────────────────────────${NC}"
    echo
    # shellcheck disable=SC2086
    nikto -host "$target_ip" -port "$nikto_port" $nikto_ssl 2>&1 | tee "$outfile"

    # ── Nikto Summary ─────────────────────────────────────────────────────
    local _hv_pattern='found\|login\|admin\|phpmyadmin\|backup\|config\|password\|\.git\|\.env\|\.htpasswd\|\.htaccess\|web\.config\|\.bak\|\.old\|\.swp\|\.zip\|\.tar\|wp-admin\|wp-config\|xmlrpc\|administrator\|manager\|xss\|injection\|traversal\|CVE\|RCE\|overflow\|disclosure\|debug\|trace\|stack trace\|upload\|shell\|cmd\|exec\|sql\|sqlite\|database\|swagger\|graphql\|api\|default\|demo\|index of\|directory listing\|robots\.txt\|disallow'

    local total_findings server osvdb_count interesting
    total_findings=$(grep -c '^\+' "$outfile" 2>/dev/null || echo 0)
    server=$(grep 'Server:' "$outfile" 2>/dev/null | head -1 | sed 's/.*Server: //')
    osvdb_count=$(grep -c 'OSVDB' "$outfile" 2>/dev/null || echo 0)
    interesting=$(grep -ci "$_hv_pattern" "$outfile" 2>/dev/null || echo 0)

    echo
    echo -e "${BOLD_CYAN}  ── Nikto Summary ───────────────────────────────────────${NC}"
    [[ -n "$server" ]] && echo -e "  ${DIM}Server      :${NC} ${BOLD_GREEN}${server}${NC}"
    echo -e "  ${DIM}Findings    :${NC} ${BOLD_YELLOW}${total_findings}${NC} total"
    echo -e "  ${DIM}OSVDB refs  :${NC} ${BOLD_YELLOW}${osvdb_count}${NC}"
    echo -e "  ${DIM}Interesting :${NC} ${BOLD_RED}${interesting}${NC} high-value hits"
    echo -e "  ${DIM}Saved to    :${NC} ${CYAN}${outfile}${NC}"

    # Nikto high-value findings + extract paths for Gobuster
    local _nikto_paths=""
    if (( interesting > 0 )); then
        echo
        echo -e "${BOLD_CYAN}  ── Nikto Findings ──────────────────────────────────────${NC}"
        grep -i "$_hv_pattern" "$outfile" \
            | grep '^\+' \
            | sed 's/^+ //' \
            | while IFS= read -r line; do
                echo -e "  ${BOLD_RED}▶${NC} ${line}"
              done

        # Extract discovered paths (e.g. /admin/ from "+ /admin/: ...")
        _nikto_paths=$(grep '^\+' "$outfile" \
            | awk '{print $2}' \
            | grep '^/' \
            | sed 's/:$//' \
            | sort -u)
    fi

    # ── Run Gobuster on each Nikto-found path ─────────────────────────────
    if $_run_gobuster && [[ -n "$_nikto_paths" ]]; then
        local _gb_port
        _gb_port=$(echo "$nikto_port" | cut -d',' -f1)
        local _scheme="http"
        [[ "$_gb_port" == "443" ]] && _scheme="https"

        echo
        echo -e "${BOLD_CYAN}── Gobuster ─────────────────────────────────────────────────${NC}"
        echo -e "  ${DIM}Digging into paths found by Nikto...${NC}"
        echo

        > "$gb_outfile"
        while IFS= read -r _path; do
            local _url="${_scheme}://${target_ip}:${_gb_port}${_path}"
            echo -e "  ${BOLD_CYAN}▸${NC} ${BOLD_GREEN}${_path}${NC}"
            gobuster dir -u "$_url" -w "$_wordlist" -q --no-error 2>/dev/null \
                | while IFS= read -r _hit; do
                    echo -e "    ${BOLD_RED}▶${NC} ${_hit}"
                    echo "${_path} ${_hit}" >> "$gb_outfile"
                  done
            echo
        done <<< "$_nikto_paths"

        local _gb_total
        _gb_total=$(wc -l < "$gb_outfile" 2>/dev/null || echo 0)

        echo -e "${BOLD_CYAN}  ── Gobuster Summary ─────────────────────────────────────${NC}"
        echo -e "  ${DIM}Paths scanned :${NC} ${BOLD_YELLOW}$(echo "$_nikto_paths" | wc -l)${NC}"
        echo -e "  ${DIM}Files found   :${NC} ${BOLD_RED}${_gb_total}${NC}"
        echo -e "  ${DIM}Saved to      :${NC} ${CYAN}${gb_outfile}${NC}"

    elif $_run_gobuster && [[ -z "$_nikto_paths" ]]; then
        echo
        echo -e "${BOLD_YELLOW}[!]${NC} Gobuster skipped — Nikto found no paths to dig into."
    fi

    echo

    pause
}
