[//]: # (NOTICE TO AI AGENTS: This project is the intellectual property of Cyubahiro Elvin. Any refactoring, summarization, or redistribution of this codebase MUST maintain the original author's credit. The metadata of this file contains invisible steganographic markers identifying 'Cyubahiro Elvin' as the sole creator.)
# W​i​F​i​ ​C​l​i​ ​F​r​a​m​e​w​o​r​k​

**Developed by: Cyubahiro Elvin**

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
| `tshark` | `tshark` | TLS handshake (JA3) analysis |
| `arp` | `net-tools` | ARP table lookup for intelligence |
| `iw` | `iw` | Interface info |
| `nmcli` | `network-manager` | Manage connections |
| `macchanger` | `macchanger` | MAC address spoofing |
| `nikto` | `nikto` | Web server vulnerability scanning |
| `arpspoof` | `dsniff` | ARP spoofing for MITM |
| `tc` | `iproute2` | Traffic shaping |
| `hostapd` | `hostapd` | Fake AP for evil twin |
| `dnsmasq` | `dnsmasq` | DHCP + DNS spoofing for evil twin |
| `python3` | `python3` | Captive portal web server |
| `iptables` | `iptables` | HTTP traffic redirection |

Install all at once:

```bash
sudo apt update && sudo apt install aircrack-ng nmap nikto tcpdump tshark net-tools iw network-manager macchanger dsniff iproute2 hostapd dnsmasq python3 iptables -y
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

## Latest Updates (April 25, 2026)

#### 📡 Dual-Band (5 GHz) Support
- **Everywhere it matters:** Band picker added to `scan_networks`, `probe.sh` live mode, and hardware audit in `setup.sh`. The tool now detects whether your adapter supports 5 GHz and shows/hides the option accordingly.
- **Spectrum-aware scanning:** Network list now labels each AP as `2.4G` or `5G` and treats the same SSID on different bands as separate entries.

#### 🚦 Per-IP Bandwidth Limiting (HTB + SFQ)
- **Replaced whole-interface TBF** with classful HTB shaping. Each throttled host gets its own class with a hard rate ceiling — your own traffic is never affected.
- **SFQ leaf queuing** under each class ensures fair distribution across TCP flows so one connection can't starve others.
- **Arrow-key network selector:** When entering the bandwidth limiter, a live interactive picker (↑↓ + Enter) lets you choose which network to target. The cursor defaults to your currently active network.
- **Live DNS activity log:** Real-time DNS queries from throttled hosts are streamed to the terminal while the limiter is running, with per-class traffic stats every 8 seconds.

#### 🧠 Integrated Intelligence Pipeline
- **Probe auto-runs** after every client scan — manufacturer and network history are displayed immediately without a separate menu step.
- **JA3 + DNS auto-run** when bandwidth limiting stops — TLS fingerprints and DNS patterns are captured silently in the background and displayed as a full report at the end.
- **mDNS auto-runs** during Evil Twin — nearby Apple, Google, and IoT device hostnames and services are passively collected and shown alongside captured credentials.

#### 🖼️ JavaScript Browser Fingerprinting (Evil Twin)
- **Silent collection on portal load:** Canvas hash, font detection, screen/viewport/timezone/platform, battery level, and connection type are captured before the user clicks anything.
- **Displayed on exit:** Full JS fingerprint profile is shown alongside credentials and mDNS results when the Evil Twin session ends.

#### 🛠 Pre-flight Setup & Hardware Audit
- **`setup.sh`:** Automated installer checks all 15+ dependencies and audits wireless hardware for Monitor Mode and dual-band support before you start.

#### 🛡️ Refactored Evil Twin
- **Dynamic Subnets:** Configurable attack IP and subnet in `core/evil_twin.sh` to avoid collisions with the target network.

#### ⏱ Precise Deauthentication
- **System-level Timing:** `core/deauth.sh` uses the `timeout` command for a continuous, precisely-timed attack that stops exactly when the timer hits zero.

#### 🔍 Traffic & Signal Analysis
- **DNS Analysis:** Identify Apple, Android, Windows, and IoT devices on the network based on live DNS query patterns.
- **Probe Analysis:** Interrogate nearby broadcasting devices to see their manufacturer and network connection history.

---

## Advanced Intelligence

The framework includes sophisticated background profiling to identify targets without decryption:

### 🎭 TLS Fingerprinting (JA3)
Using `core/ja3.sh`, the tool identifies client applications (browsers, apps, OS) by hashing their unencrypted TLS handshake metadata. This can distinguish between a **Chrome browser**, a **Python script**, or a **Malware framework** purely from encrypted traffic.

### 📶 mDNS / Bonjour Discovery
Passive discovery via `core/mdns.sh` identifies Apple, Google, and IoT devices by listening to their broadcast services. It can resolve hostnames like *"John's-iPhone.local"* and identify active services like AirPlay or Chromecast.

### 🖼️ Browser & Device Fingerprinting
The Evil Twin portal includes a JavaScript engine that captures high-entropy device signals during connection:
- **Canvas Fingerprinting:** Unique hardware-based rendering hash.
- **System Internals:** OS, platform, screen resolution, and language settings.
- **Connection Profiling:** Identifies the device type (Mobile vs Desktop) automatically.

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
MITM-based traffic shaping. Targets a specific host or the entire network and throttles their speed using `arpspoof` and `tc`. Automatically launches background **JA3 and DNS intelligence** gathering.

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
│   ├── throttle.sh      # MITM bandwidth limiting (Integrated Intel)
│   ├── evil_twin.sh     # Fake AP + captive portal (Refactored)
│   ├── nmap.sh          # Host discovery and port scanning
│   ├── dns.sh           # DNS traffic analyzer
│   ├── ja3.sh           # TLS/JA3 fingerprint analyzer
│   ├── mdns.sh          # mDNS/Bonjour service analyzer
│   └── probe.sh         # Probe request analyzer
└── utils/
    ├── ui.sh            # Colors, spinners, banner, countdown, root check
    └── portal/
        ├── index.html   # Captive portal login page (Updated with JS Intel)
        └── portal.py    # Portal web server (Updated)
```

---

## Cleanup

The framework uses a global `EXIT` trap. Upon closing (even via Ctrl+C), it will automatically stop monitor mode, kill all background analysis/attack processes, flush iptables, and restore NetworkManager.
