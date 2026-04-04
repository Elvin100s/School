#!/bin/bash

# Colors
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD_CYAN='\033[1;36m'
NC='\033[0m'

check_root() {
if [[ $EUID -ne 0 ]]; then
echo "Run as root"
exit 1
fi
}

pause() {
read -p "Press enter to continue..."
}