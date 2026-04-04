#!/bin/bash

enable_monitor() {

if [[ -z "$iface" ]]; then
echo "Select interface first!"
pause
return
fi

if iw dev "$iface" info 2>/dev/null | grep -q "type monitor"; then
echo "[$iface] is already in monitor mode!"
pause
return
fi

clear
echo "[+] Killing interfering processes..."
echo

# Save current connection profile before killing processes
saved_conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1)

airmon-ng check kill

echo
echo "[+] Enabling monitor mode on $iface"
echo

airmon-ng start "$iface"

sleep 2

# detect monitor interface
mon_iface=$(iw dev | awk '$1=="Interface"{print $2}' | grep -E "mon|$iface" | head -n 1)

if [[ -z "$mon_iface" ]]; then
echo
echo "Monitor mode failed!"
pause
return
fi

echo
echo "Monitor interface: $mon_iface"
pause
}

stop_monitor() {

if [[ -z "$mon_iface" ]]; then
echo "No monitor interface active!"
pause
return
fi

clear
echo "[+] Stopping monitor mode..."
echo

airmon-ng stop "$mon_iface"

echo
echo "[+] Restoring NetworkManager..."
systemctl start NetworkManager
sleep 2
if [[ -n "$saved_conn" ]]; then
    echo "[+] Reconnecting to $saved_conn..."
    nmcli connection up "$saved_conn" 2>/dev/null
fi

# reset variable
mon_iface=""