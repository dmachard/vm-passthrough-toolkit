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
perf_script="/etc/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin/cpu-perf-mode.sh"
normal_script="/etc/libvirt/hooks/qemu.d/$VM_NAME/release/end/cpu-normal-mode.sh"

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

info "Updating CPU pinning to P‑cores set \"$pcores_list\"…"

if [[ -z "${TEMP_XML:-}" || ! -f "$TEMP_XML" ]]; then
    TEMP_XML=$(mktemp)
    virsh dumpxml "$VM_NAME" > "$TEMP_XML"
fi

VCPU_COUNT=$(virsh dominfo "$VM_NAME" | awk '/^CPU\(s\)/ {print $2}')

sed -i '/<cputune>/,/<\/cputune>/d' "$TEMP_XML"


CPU_XML=$(mktemp)
{
    echo "  <cputune>"
    for ((i=0; i<VCPU_COUNT; i++)); do
        echo "    <vcpupin vcpu='$i' cpuset='$pcores_list'/>"
    done
    echo "    <emulatorpin cpuset='$pcores_list'/>"
    echo "  </cputune>"
} > "$CPU_XML"

sed -i "/<\/vcpu>/r $CPU_XML" "$TEMP_XML"
rm -f "$CPU_XML"

info "CPU pinning XML block added (${VCPU_COUNT} vCPU → cpuset $pcores_list)"
if [[ -f "${TEMP_XML:-}" ]]; then
    info "Applying VM configuration changes..."
    virsh define "$TEMP_XML" >> "$LOGFILE" 2>&1
    rm "$TEMP_XML"
    success "VM configuration updated successfully"
fi
success "CPU pinning and libvirt hooks setup complete."