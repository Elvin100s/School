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

Install all at once on Debian/Kali/Parrot:

```bash
sudo apt update && sudo apt install aircrack-ng nmap iw network-manager -y
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
  1) Quick Wizard        — automated start-to-finish workflow
  2) Manual Mode         — step-by-step control over each stage

-- Network Recon --
  3) Host Discovery      — nmap ping scan on your subnet
  4) Port Scan Host      — nmap service scan on a selected host

  5) Exit
```

### Quick Wizard
Walks through the full wireless workflow automatically:
1. Select interface
2. Enable monitor mode
3. Scan for nearby networks
4. Select a target
5. Scan for connected clients
6. Choose deauth action

### Manual Mode
Full step-by-step control, organized into stages:

**Setup**
- Select interface, enable/stop monitor mode

**Wireless Recon**
- Scan networks, select a target BSSID, scan clients

**Network Recon**
- Host discovery and port scanning via nmap

**Attack**
- Deauth all clients or a single selected client

---

## Project Structure

```
wifi-cli/
├── wifi-cli.sh          # Entry point, global state, cleanup trap
├── core/
│   ├── interface.sh     # Wireless interface selection
│   ├── monitor.sh       # Monitor mode management
│   ├── scan.sh          # Network and target scanning
│   ├── clients.sh       # Client enumeration
│   ├── deauth.sh        # Deauth attacks + menu definitions
│   └── nmap.sh          # Host discovery and port scanning
└── utils/
    └── ui.sh            # Colors, root check, pause helper
```

---

## Cleanup

The script automatically restores your wireless interface on exit (Ctrl+C or normal exit):
- Stops monitor mode
- Restarts NetworkManager
- Reconnects to your previous saved connection
