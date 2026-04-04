#!/bin/bash

select_interface() {

clear
echo "====== Select Interface ======"
echo

# Get all wireless interfaces
interfaces=($(iw dev | awk '$1=="Interface"{print $2}'))

if [ ${#interfaces[@]} -eq 0 ]; then
    echo "No wireless interfaces found!"
    pause
    return
fi

# List interfaces with numbers
for i in "${!interfaces[@]}"; do
    echo "$((i+1))) ${interfaces[$i]}"
done

echo
read -p "Choice: " num

# Map number to interface
iface=${interfaces[$((num-1))]}

if [[ -z "$iface" ]]; then
    echo "Invalid selection!"
    pause
    return
fi

echo
echo "Selected interface: $iface"
pause
}