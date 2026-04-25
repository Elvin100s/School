# Project Memory: wifi-cli

### Latest Engineering Changes (April 24, 2026)

#### 🛠 Infrastructure & Setup
- **`core/deauth.sh`:** Refactored timed deauthentication to use the `timeout` command. This replaces the previous inefficient burst-loop with a continuous, precisely-timed attack.
- **`setup.sh`:** Introduced a mandatory pre-flight script. It automates the installation of 15+ dependencies and performs a hardware audit to verify if wireless adapters support **Monitor Mode**.
- **`README.md`:** Updated with the new setup workflow and detailed documentation for the traffic analysis modules.

#### 🛡️ Evil Twin Refactor
- **Subnet Configuration:** Hardcoded `192.168.1.1` IPs were replaced with variables (`ET_IP`, `ET_NET`, `ET_RANGE`) in `core/evil_twin.sh`.
- **Portal Server:** `utils/portal/portal.py` was updated to accept the gateway IP as a command-line argument, allowing the captive portal to bind and redirect dynamically.

#### 📡 New Analysis Modules
- **`core/dns.sh`:** Real-time DNS traffic analysis. Uses heuristic patterns to fingerprint devices (Apple, Android, Windows, IoT, etc.) and lists top queried domains.
- **`core/probe.sh`:** Analyzes unencrypted 802.11 probe requests to identify device manufacturers and their connection histories (previously known SSIDs).

#### 🏗️ Architecture Note
- The `cleanup()` trap in `wifi-cli.sh` is the "source of truth" for system restoration. Any new background processes must be added to this trap to ensure the user's networking is restored on exit.
