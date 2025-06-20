#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

###############################################################################
# CPU detection
###############################################################################

info "CPU Pinning..."

# Load configuration
CONFIG_FILE="/etc/passthrough/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

cpu_model_str=$(awk -F: '/model name/{print $2;exit}' /proc/cpuinfo | xargs)
cpu_vendor=$(awk -F: '/vendor_id/{print $2;exit}' /proc/cpuinfo | xargs)
total_cores=$(nproc)

info "=== CPU Detection ==="
info "Model string : $cpu_model_str"
info "Vendor       : $cpu_vendor"
info "Cores        : $total_cores"

pcores_list=""
ecores_list=""

# Check for Intel hybrid architecture (P‑cores + E‑cores)
if [[ -r /sys/devices/cpu_core/cpus ]]; then
  pcores_list=$(< /sys/devices/cpu_core/cpus)
fi
if [[ -r /sys/devices/cpu_atom/cpus ]]; then
  ecores_list=$(< /sys/devices/cpu_atom/cpus)
fi

# Fallback for AMD / non‑hybrid: use all online CPUs as P‑cores
if [[ -z "$pcores_list" && -z "$ecores_list" ]]; then
  pcores_list=$(cat /sys/devices/system/cpu/online)
  info "Hybrid core files absent → treating all cores as P‑cores: $pcores_list"
else
  info "P‑cores ranges: $pcores_list"
  info "E‑cores ranges: $ecores_list"
fi

###############################################################################
# Install libvirt master hook
###############################################################################
HOOK_DIR="/etc/libvirt/hooks"
HOOK_MAIN="$HOOK_DIR/qemu"
VM_HOOK_BASE="$HOOK_DIR/qemu.d/$VM_NAME"
PREPARE_DIR="$VM_HOOK_BASE/prepare/begin"
RELEASE_DIR="$VM_HOOK_BASE/release/end"
perf_script="$PREPARE_DIR/cpu-perf-mode.sh"
normal_script="$RELEASE_DIR/cpu-normal-mode.sh"

sudo mkdir -p "$HOOK_DIR"
sudo wget -q 'https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/qemu' \
     -O "$HOOK_MAIN"
sudo chmod +x "$HOOK_MAIN"
info "Installed master libvirt hook: $HOOK_MAIN"

sudo mkdir -p "$PREPARE_DIR" "$RELEASE_DIR"

cat > "$perf_script" <<EOF
#!/bin/bash
set -e
echo "[+] Enable performance mode (restrict host to selected cores)" | systemd-cat -t vm-hook
systemctl set-property --runtime -- user.slice AllowedCPUs="$ecores_list"
systemctl set-property --runtime -- system.slice AllowedCPUs="$ecores_list"
systemctl set-property --runtime -- init.scope AllowedCPUs="$ecores_list"
cpupower frequency-set -g performance
systemctl show --property AllowedCPUs user.slice | systemd-cat -t vm-hook
systemctl show --property AllowedCPUs system.slice | systemd-cat -t vm-hook
systemctl show --property AllowedCPUs init.scope | systemd-cat -t vm-hook
echo "[+] perf-mode activated" | systemd-cat -t vm-hook
EOF

cat > "$normal_script" <<EOF
#!/bin/bash
set -e
echo "[+] Restore powersave mode (all cores)"  | systemd-cat -t vm-hook
systemctl set-property --runtime -- user.slice AllowedCPUs="$pcores_list $ecores_list"
systemctl set-property --runtime -- system.slice AllowedCPUs="$pcores_list $ecores_list"
systemctl set-property --runtime -- init.scope AllowedCPUs="$pcores_list $ecores_list"
cpupower frequency-set -g powersave
systemctl show --property AllowedCPUs user.slice | systemd-cat -t vm-hook
systemctl show --property AllowedCPUs system.slice | systemd-cat -t vm-hook
systemctl show --property AllowedCPUs init.scope | systemd-cat -t vm-hook
echo "[+] perf-mode disabled" | systemd-cat -t vm-hook
EOF

chmod +x "$perf_script" "$normal_script"

info "VM‑specific hooks installed under $VM_HOOK_BASE"
success "CPU pinning and libvirt hooks setup complete."