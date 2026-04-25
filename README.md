# WiFi CLI Framework

A menu-driven bash framework for wireless reconnaissance and network attacks, built around the aircrack-ng suite and nmap.

> **For authorized use only.** Only run this against networks and devices you own or have explicit written permission to test.

---

## Requirements

### OS
- Linux (Kali, Parrot, or any Debian-based distro recommended)
- Must be run as **root**

### Hardware
- A wireless NIC that supports **monitor mode** and **packet injection**

### Dependencies

| Tool | Package | Purpose |
|---|---|---|
| `airmon-ng` | `aircrack-ng` | Enable/disable monitor mode |
| `airodump-ng` | `aircrack-ng` | Scan networks and clients |
| `aireplay-ng` | `aircrack-ng` | Deauthentication |
| `nmap` | `nmap` | Host discovery and port scanning |
| `tcpdump` | `tcpdump` | Packet capture for DNS analysis |
| `arp` | `net-tools` | ARP table lookup for DNS analysis |
| `iw` | `iw` | Interface info |
| `nmcli` | `network-manager` | Manage connections |
| `macchanger` | `macchanger` | MAC address spoofing |
| `arpspoof` | `dsniff` | ARP spoofing for bandwidth limiting |
| `tc` | `iproute2` | Traffic shaping |
| `hostapd` | `hostapd` | Fake AP for evil twin |
| `dnsmasq` | `dnsmasq` | DHCP + DNS spoofing for evil twin |
| `python3` | `python3` | Captive portal web server |
| `iptables` | `iptables` | HTTP traffic redirection |

Install all at once:

```bash
sudo apt update && sudo apt install aircrack-ng nmap tcpdump net-tools iw network-manager macchanger dsniff iproute2 hostapd dnsmasq python3 iptables -y
```

---

## Setup

```bash
git clone <repo-url>
cd wifi-cli
chmod +x setup.sh wifi-cli.sh

# Run the pre-flight check and installer
sudo ./setup.sh
```

---

## Usage

```bash
sudo ./wifi-cli.sh
```

---

## Latest Updates (April 24, 2026)

#### 🛠 Pre-flight Setup & Hardware Audit
- **`setup.sh`:** A new automated installer that checks for all 15+ dependencies and audits your WiFi hardware to confirm it supports **Monitor Mode** before you start.

#### 🛡️ Refactored Evil Twin
- **Dynamic Subnets:** You can now modify the attack IP and subnet in `core/evil_twin.sh` to avoid collisions with the target network.
- **Improved Portal:** The Python portal server now binds dynamically to the configured gateway IP.

#### ⏱ Precise Deauthentication
- **System-level Timing:** Refactored `core/deauth.sh` to use the `timeout` command. This replaces the old burst-loop with a continuous, precisely-timed attack that stops exactly when the timer hits zero.

#### 🔍 Traffic & Signal Analysis
- **DNS Analysis:** Identify Apple, Android, Windows, and IoT devices on the network based on live DNS query patterns.
- **Probe Analysis:** Interrogate nearby broadcasting devices to see their manufacturer and network connection history.

---

## Features

### Quick Wizard
Fully automated start-to-finish workflow:
1. Interface auto-selected, MAC spoofed, monitor mode enabled
2. Scan for nearby networks
3. Select a target
4. Scan for all clients on the channel
5. Attack menu (Deauth ALL / Deauth One)

### Manual Mode
Step-by-step control over the reconnaissance and attack phases. Includes **Host Discovery**, **Port Scanning**, and the new **Traffic Analysis** suite.

### Bandwidth Limiter
MITM-based traffic shaping. Targets a specific host or the entire network and throttles their speed to "Slow", "Painful", or "Crawl" using `arpspoof` and `tc`.

---

## Project Structure

```
wifi-cli/
├── wifi-cli.sh          # Entry point, global state, cleanup trap
├── setup.sh             # Pre-flight installer and hardware auditor
├── core/
│   ├── interface.sh     # Wireless interface selection
│   ├── monitor.sh       # Monitor mode + MAC spoofing
│   ├── scan.sh          # Network and target scanning
│   ├── clients.sh       # Client enumeration
│   ├── deauth.sh        # Deauth attacks (Refactored Timing)
│   ├── throttle.sh      # MITM bandwidth limiting
│   ├── evil_twin.sh     # Fake AP + captive portal (Refactored)
│   ├── nmap.sh          # Host discovery and port scanning
│   ├── dns.sh           # DNS traffic analyzer
│   └── probe.sh         # Probe request analyzer
└── utils/
    ├── ui.sh            # Colors, spinners, banner, countdown, root check
    └── portal/
        ├── index.html   # Captive portal login page
        └── portal.py    # Portal web server (Updated)
```

---

## Cleanup

The framework uses a global `EXIT` trap. Upon closing (even via Ctrl+C), it will:
- Stop monitor mode and restart NetworkManager.
- Kill all `hostapd`, `dnsmasq`, and `python` portal processes.
- Flush `iptables` rules and reset IP forwarding.
- Remove all `tc` traffic shaping and ARP spoofing rules.
