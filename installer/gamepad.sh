#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

info "Installing Gamepad VM Passthrough..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Copy script
info "Installing script..."
cp scripts/attach_gamepad.sh /usr/local/bin/
chmod +x /usr/local/bin/attach_gamepad.sh

# Copy udev rules  
info "Installing udev rules..."
cp udev/99-gamepad-vm.rules /etc/udev/rules.d/

# Reload udev
info "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger