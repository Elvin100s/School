# WiFi CLI Framework

A menu-driven bash framework for wireless reconnaissance and network scanning, built around the aircrack-ng suite and nmap.

> **For authorized use only.** Only run this against networks and devices you own or have explicit written permission to test.

> Now that the boring legal stuff is out of the way — have fun with it.

---

## Requirements

### OS
- Linux (Kali, Parrot, or any Debian-based distro recommended)
- Must be run as **root**

### Hardware
- A wireless NIC that supports **monitor mode** and **packet injection**
  - Common compatible chipsets: Alfa AWUS036ACH, TP-Link TL-WN722N v1, Panda PAU09

### Dependencies

| Tool | Package | Purpose |
|---|---|---|
| `airmon-ng` | `aircrack-ng` | Enable/disable monitor mode |
| `airodump-ng` | `aircrack-ng` | Scan networks and clients |
| `aireplay-ng` | `aircrack-ng` | Deauthentication |
| `nmap` | `nmap` | Host discovery and port scanning |
| `iw` | `iw` | Interface info |
| `nmcli` | `network-manager` | Manage connections |
| `macchanger` | `macchanger` | MAC address spoofing |
| `arpspoof` | `dsniff` | ARP spoofing for bandwidth limiting |
| `tc` | `iproute2` | Traffic shaping (usually pre-installed) |
| `hostapd` | `hostapd` | Fake AP for evil twin |
| `dnsmasq` | `dnsmasq` | DHCP + DNS spoofing for evil twin |
| `python3` | `python3` | Captive portal web server |
| `iptables` | `iptables` | HTTP traffic redirection (usually pre-installed) |

Install all at once on Debian/Kali/Parrot:

```bash
sudo apt update && sudo apt install aircrack-ng nmap iw network-manager macchanger dsniff iproute2 hostapd dnsmasq python3 iptables -y
```

---

## Setup

```bash
git clone <repo-url>
cd wifi-cli
chmod +x wifi-cli.sh
```

---

## Usage

```bash
sudo ./wifi-cli.sh
```

### Main Menu

```
  [1] Quick Wizard        — automated start-to-finish workflow
  [2] Manual Mode         — step-by-step control over each stage
  [3] Evil Twin           — fake AP + captive portal password capture

  -- Network Recon --
  [4] Host Discovery      — nmap ping scan on your subnet
  [5] Port Scan Host      — nmap service scan on a selected host

  -- Bandwidth Limiter --
  [6] Bandwidth Limiter   — MITM traffic shaping (managed mode)

  [7] Exit
```

### Quick Wizard
Walks through the full wireless workflow automatically:
1. Interface selection + monitor mode enabled automatically
2. Scan for nearby networks (adjustable duration: 10s / 20s / 45s)
3. Select a target — networks with multiple APs automatically resolve to the strongest signal
4. Scan for all clients on the channel (adjustable duration)
5. Attack menu appears immediately after the client list

Attack menu:
```
  [1] Deauth ALL
  [2] Deauth One Client

  [3] Re-scan Clients          — re-run client scan on current channel
  [4] Change Target            — pick from existing scan, no full re-scan
  [5] Full Re-scan             — fresh airodump from scratch

  [6] Back to Main Menu
```

### Manual Mode
Interface selection and monitor mode run automatically on entry — no manual setup needed.

**Wireless Recon**
- Scan networks — results sorted by signal strength (strongest first), color coded by dBm
- Select a target BSSID
- Scan clients — drops straight into the attack menu after the client list is shown

**Network Recon**
- Host discovery and port scanning via nmap

**Attack**
- Deauth all clients on a selected network or a specific client
- If multiple networks were seen in the client scan, `Deauth ALL` shows a network picker first
- After picking a deauth option, choose mode:
  - **Continuous** — runs until Ctrl+C (default)
  - **Timed** — pick 10s / 30s / 60s / custom, stops automatically
- Confirmation prompt + 3-2-1 countdown before executing

### Evil Twin
Spins up a fake AP with the exact same SSID as a real network to capture the WiFi password via a captive portal.

1. Pick a target from the network scan list
2. Sends a deauth burst to knock clients off the real network
3. Switches card out of monitor mode and starts a fake AP with the same SSID
4. Any client that connects gets served a captive portal — a login page asking them to re-enter their WiFi password
5. Submitted password is captured, verified, and saved to `wifi-cli-captures.log`

Requires: `hostapd`, `dnsmasq`, `python3`, `iptables`

---

### Bandwidth Limiter
Requires managed mode (card connected to the network, not in monitor mode). Accessible from the main menu.
- Discovers all hosts on your subnet via nmap
- Pick one host or all hosts
- Pick throttle level:
  - **Slow** — 512 KB/s
  - **Painful** — 128 KB/s
  - **Crawl** — 32 KB/s
  - **Custom** — enter KB/s manually
- ARP poisons the target and applies `tc` rate limiting — target stays connected, just slower
- Press Enter to stop — cleans up ARP spoof, tc rules, and IP forwarding automatically

### Client Scanning
- Unassociated/probing devices are automatically filtered out — only clients actually connected to an AP are shown
- Networks with multiple access points (mesh, range extenders) are deduplicated by ESSID — the strongest AP is selected automatically
- HT40 channel suffixes (e.g. `6+1`, `11-1`) are stripped and handled correctly
- Scan duration is adjustable: 10s / 20s / 45s

---

## Project Structure

```
wifi-cli/
├── wifi-cli.sh          # Entry point, global state, cleanup trap
├── core/
│   ├── interface.sh     # Wireless interface selection
│   ├── monitor.sh       # Monitor mode + MAC spoofing
│   ├── scan.sh          # Network and target scanning
│   ├── clients.sh       # Client enumeration
│   ├── deauth.sh        # Deauth attacks + menu definitions
│   ├── throttle.sh      # MITM bandwidth limiting
│   ├── evil_twin.sh     # Fake AP + captive portal
│   └── nmap.sh          # Host discovery and port scanning
└── utils/
    ├── ui.sh            # Colors, spinners, banner, countdown, root check
    └── portal/
        ├── index.html   # Captive portal login page
        └── portal.py    # Portal web server
```

---

## Cleanup

Ctrl+C works at any point. On exit the script automatically:
- Stops monitor mode
- Restarts NetworkManager
- Reconnects to your previous saved connection
- Kills any active ARP spoof processes
- Removes tc traffic shaping rules
- Disables IP forwarding
