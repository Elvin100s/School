#!/bin/bash

# Colors
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
BOLD_RED='\033[1;31m'
GREEN='\033[0;32m'
BOLD_GREEN='\033[1;32m'
YELLOW='\033[0;33m'
BOLD_YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
MAGENTA='\033[0;35m'
BOLD_MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
NC='\033[0m'

_TAGLINES=(
    "wireless recon framework"
    "the air belongs to everyone"
    "because wifi is just air with boundaries"
    "making routers uncomfortable since day one"
    "the quieter you become, the more you can hear"
    "not all who wander are lost — some are just scanning"
    "packet sniffing as a lifestyle"
    "your neighbor's wifi is not your wifi... or is it?"
    "hunting signals in the dark"
    "listening to things that weren't meant for you"
)

print_banner() {
    local tagline="${_TAGLINES[$((RANDOM % ${#_TAGLINES[@]}))]}"
    echo -e "
${BOLD_CYAN} ██╗    ██╗██╗███████╗██╗      ██████╗██╗     ██╗
 ██║    ██║██║██╔════╝██║     ██╔════╝██║     ██║
 ██║ █╗ ██║██║█████╗  ██║     ██║     ██║     ██║
 ██║███╗██║██║██╔══╝  ██║     ██║     ██║     ██║
 ╚███╔███╔╝██║██║     ██║     ╚██████╗███████╗██║
  ╚══╝╚══╝ ╚═╝╚═╝     ╚═╝      ╚═════╝╚══════╝╚═╝${NC}
${DIM}              ${tagline}${NC}
"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${BOLD_RED}[!] Run as root${NC}"
        exit 1
    fi
}

pause() {
    echo
    read -p "  Press enter to continue..."
}

# Draw a box around status fields
draw_status_box() {
    local width=45
    local border="${BOLD_CYAN}│${NC}"
    local top="${BOLD_CYAN}┌$(printf '─%.0s' $(seq 1 $width))┐${NC}"
    local bot="${BOLD_CYAN}└$(printf '─%.0s' $(seq 1 $width))┘${NC}"

    echo -e "$top"

    _status_row() {
        local label="$1"
        local value="$2"
        local color="$3"
        # strip ANSI for length calc
        local plain_val
        plain_val=$(echo -e "$value" | sed 's/\x1b\[[0-9;]*m//g')
        local plain_label
        plain_label=$(echo -e "$label" | sed 's/\x1b\[[0-9;]*m//g')
        local content="${label}${color}${plain_val}${NC}"
        local pad=$(( width - ${#plain_label} - ${#plain_val} - 1 ))
        printf "${border}  ${content}$(printf ' %.0s' $(seq 1 $pad))${border}\n"
    }

    local iface_val="${iface:-${YELLOW}Not set${NC}}"
    local iface_color="${iface:+${BOLD_GREEN}}"
    _status_row "${DIM}Interface : ${NC}" "${iface:-Not set}" "${iface:+${BOLD_GREEN}}"

    local mon_val="${mon_iface:-Not set}"
    _status_row "${DIM}Monitor   : ${NC}" "${mon_iface:-Not set}" "${mon_iface:+${BOLD_GREEN}}"

    local tgt_val="${bssid:-Not set}"
    _status_row "${DIM}Target    : ${NC}" "${bssid:-Not set}" "${bssid:+${BOLD_GREEN}}"

    local ch_val="${channel:-Not set}"
    _status_row "${DIM}Channel   : ${NC}" "${channel:-Not set}" "${channel:+${BOLD_GREEN}}"

    echo -e "$bot"
}

# Section divider
section() {
    local label="$1"
    local width=43
    local plain_label
    plain_label=$(echo -e "$label" | sed 's/\x1b\[[0-9;]*m//g')
    local line_len=$(( (width - ${#plain_label} - 2) ))
    local right_line
    right_line=$(printf '─%.0s' $(seq 1 $line_len))
    echo -e "  ${DIM}── ${label}${DIM} ${right_line}${NC}"
}

_SCAN_FLAVORS=(
    "sniffing the airwaves"
    "interrogating the spectrum"
    "listening to things not meant for us"
    "asking packets nicely"
    "patience. they will show themselves."
    "hunting signals in the dark"
    "watching the invisible"
    "reading the air"
)

# Pick a random scan flavor message
scan_flavor() {
    echo "${_SCAN_FLAVORS[$((RANDOM % ${#_SCAN_FLAVORS[@]}))]}"
}

# 3-2-1 countdown before a deauth fires
deauth_countdown() {
    echo
    tput civis 2>/dev/null
    for i in 3 2 1; do
        printf "\r  ${BOLD_RED}firing in ${i}...${NC}  "
        sleep 0.7
    done
    printf "\r  ${BOLD_RED}▓▓▓▓▓▓▓▓▓▓ FIRING ▓▓▓▓▓▓▓▓▓▓${NC}\n"
    tput cnorm 2>/dev/null
    echo
}

# Flash shown when clients are found
target_acquired() {
    echo
    echo -e "  ${BOLD_RED}[ TARGET ACQUIRED ]${NC}"
    sleep 0.4
}

_EXIT_MSGS=(
    "cleaning up and going dark."
    "leaving no trace... probably."
    "packing up the antennas."
    "back to being invisible."
    "the packets were never there."
    "until next time."
)

# Random exit message
exit_msg() {
    echo "${_EXIT_MSGS[$((RANDOM % ${#_EXIT_MSGS[@]}))]}"
}

# Spinner for long-running background tasks
# Usage: spinner $pid "message"
spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BOLD_CYAN}${frames[$i]}${NC}  ${msg}"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.1
    done
    printf "\r  ${BOLD_GREEN}✔${NC}  ${msg}\n"
    tput cnorm 2>/dev/null
}
