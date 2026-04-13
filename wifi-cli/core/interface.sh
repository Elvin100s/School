#!/bin/bash

select_interface() {

clear
echo -e "${BOLD_CYAN}====== Select Interface ======${NC}"
echo

# Get all wireless interfaces
interfaces=($(iw dev | awk '$1=="Interface"{print $2}'))

if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${BOLD_RED}[!]${NC} No wireless interfaces found!"
    pause
    return
fi

# List interfaces with numbers
for i in "${!interfaces[@]}"; do
    echo -e "  ${BOLD_CYAN}$((i+1)))${NC} ${interfaces[$i]}"
done

echo
read -p "  Choice: " num

# Map number to interface
iface=${interfaces[$((num-1))]}

if [[ -z "$iface" ]]; then
    echo -e "${BOLD_RED}[!]${NC} Invalid selection!"
    pause
    return
fi

echo
echo -e "${BOLD_GREEN}[+]${NC} Selected interface: ${BOLD_GREEN}${iface}${NC}"
pause
}