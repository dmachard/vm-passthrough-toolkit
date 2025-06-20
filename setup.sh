#!/usr/bin/env bash
# VM Passthrough Toolkit – unified installer

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$PROJECT_DIR/installer"
source "$(dirname "${BASH_SOURCE[0]}")/installer/common.sh"

usage() {
  cat <<EOF
VM Passthrough Toolkit – Setup Script

Usage: $(basename "$0") [OPTIONS]

OPTIONS
  --all          Configure all passthrough modules (GPU + gamepad)
  --gpu          Configure GPU passthrough
  --cpu          Configure CPU passthrough
  --gamepad      Configure gamepad passthrough
  --hugepages    Configure hugepages memory backing
  -h, --help     Show this help message

Examples
  $(basename "$0") --all
  $(basename "$0") --gpu
EOF
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌  This script must be run as root (or via sudo)." >&2
    exit 1
  fi
}

check_os() {
    info "Checking OS prerequisites..."

    # Check if running on Ubuntu/Debian
    if ! command -v apt-get &> /dev/null; then
        error "This script is designed for Ubuntu/Debian systems"
    fi

    # Check for minimum RAM (16GB recommended)
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 16 ]]; then
        error "Less than 16GB RAM detected ($total_ram GB). Performance may be limited."
    else
        success "RAM: ${total_ram}GB (sufficient)"
    fi
}

check_dep() {
  local cmd=$1
  if ! command -v "$cmd" &>/dev/null; then
    error "- Dependency '$cmd' is not installed. Install it and re‑run." >&2
    exit 1
  fi
}

# Check if the VM is defined (exists in libvirt)
vm_exists() {
  virsh list --all --name | grep -Fxq "$VM_NAME"
}

require_vm_exists() {
  if vm_exists; then
    success "VM '$VM_NAME' exists."
  else
    error "VM '$VM_NAME' does not exist. Check the VM name or define it using virt-manager or virsh."
    exit 1
  fi
}

setup_libvirt_hooks() {
  HOOK_DIR="/etc/libvirt/hooks"
  HOOK_MAIN="$HOOK_DIR/qemu"
  HOOK_BASE="$HOOK_DIR/qemu.d/$VM_NAME"
 
  sudo mkdir -p "$HOOK_DIR"
  sudo wget -q 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu' \
      -O "$HOOK_MAIN"
  sudo chmod +x "$HOOK_MAIN"

  # Create libvirt hooks directories
  mkdir -p $HOOK_BASE/{prepare/begin,release/end}
  info "Installed master libvirt hook"
}

main() {
  local DO_GPU=0
  local DO_CPU=0
  local DO_GAMEPAD=0
  local DO_HUGEPAGES=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)       DO_GPU=1; DO_CPU=1; DO_GAMEPAD=1 ;;
      --gpu)       DO_GPU=1 ;;
      --cpu)       DO_CPU=1 ;;
      --gamepad)   DO_GAMEPAD=1 ;;
      --hugepages) DO_HUGEPAGES=1 ;;
      -h|--help)   usage; exit 0 ;;
      *)           error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done

  require_root

  info "Starting hardware detection..."
  check_os

  info "Checking base dependencies..."
  for dep in qemu-system-x86_64 virsh modprobe; do
    check_dep "$dep"
  done

  # Copy example config if config doesn't exist
  info "Creating directories..."
  mkdir -p /etc/passthrough

  CONFIG_FILE="/etc/passthrough/config.conf"
  cp config/config.conf /etc/passthrough/config.conf
  source "$CONFIG_FILE"

  require_vm_exists
  setup_libvirt_hooks
  chmod +x ./installer/*

  [[ $DO_CPU -eq 1 ]]     && "$INSTALLER_DIR/cpu.sh"
  [[ $DO_GPU -eq 1 ]]     && "$INSTALLER_DIR/gpu.sh"
  [[ $DO_GAMEPAD -eq 1 ]] && "$INSTALLER_DIR/gamepad.sh"
  [[ $DO_HUGEPAGES -eq 1 ]] && "$INSTALLER_DIR/hugepages.sh"

  success "Setup completed successfully!"
}

main "$@"
