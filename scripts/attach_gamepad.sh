#!/bin/bash

# Gamepad VM Passthrough - Attach Script
# Automatically attaches USB gamepads to libvirt VMs

# =============================================================================
# CONFIGURATION
# =============================================================================

CONFIG_FILE="/etc/passthrough/config.conf"
DEFAULT_VM="win10-gaming"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Set defaults if not configured
VM_NAME="${VM_NAME:-$DEFAULT_VM}"
LOGFILE="${LOGFILE:-$DEFAULT_LOGFILE}"
SYS_PATH="$1"

echo "Using VM: ${VM_NAME:-$DEFAULT_VM}" >> "$LOGFILE"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOGFILE"
}

log_message "=== DEBUG UDEV ENVIRONMENT ==="
log_message "Date: $(date)"
log_message "User: $(whoami)"
log_message "PATH: $PATH"
log_message "HOME: $HOME"
log_message "Args: $@"
log_message "virsh location: $(which virsh 2>&1)"
log_message "virsh test: $(virsh list 2>&1)"
log_message "==================================="


log_message "Gamepad attachment triggered for $SYS_PATH"

# Validate sysfs path
if [[ ! -d "/sys$SYS_PATH" ]]; then
    log_message "Error: Invalid sysfs path: $SYS_PATH"
    exit 1
fi

# Check VM state
log_message "Checking VM state for $VM_NAME..."
vm_state=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "not_found")
vm_ret=$?

if [[ $vm_ret -ne 0 || "$vm_state" == "not_found" ]]; then
    log_message "Error: VM $VM_NAME not found or inaccessible"
    exit 1
fi

if [[ "$vm_state" != "running" ]]; then
    log_message "Error: VM $VM_NAME is not running (state: $vm_state)"
    exit 1
fi

log_message "VM $VM_NAME is running"

# Extract USB bus and device numbers
bus=$(udevadm info -q property -p "/sys$SYS_PATH" | grep BUSNUM | cut -d= -f2)
device=$(udevadm info -q property -p "/sys$SYS_PATH" | grep DEVNUM | cut -d= -f2)

if [[ -z "$bus" || -z "$device" ]]; then
    log_message "Error: Could not extract USB bus/device for $SYS_PATH"
    exit 1
fi

# Convert to decimal (remove leading zeros)
bus_dec=$((10#$bus))
device_dec=$((10#$device))
DEV_PATH="/dev/bus/usb/$(printf "%03d" $bus_dec)/$(printf "%03d" $device_dec)"

log_message "USB Info - Bus: $bus_dec, Device: $device_dec, Path: $DEV_PATH"

# Generate libvirt XML for USB passthrough
TMP_XML=$(mktemp)
cat <<EOF > "$TMP_XML"
<hostdev mode='subsystem' type='usb' managed='no'>
  <source>
    <address bus='$bus_dec' device='$device_dec'/>
  </source>
</hostdev>
EOF

log_message "Generated XML for USB passthrough:"
cat "$TMP_XML" >> "$LOGFILE"

# Attach device to VM
log_message "Attaching gamepad to VM $VM_NAME..."
if virsh attach-device "$VM_NAME" "$TMP_XML" --live 2>>"$LOGFILE"; then
    log_message "Gamepad successfully attached to $VM_NAME"
else
    log_message "Failed to attach gamepad to $VM_NAME"
    rm -f "$TMP_XML"
    exit 1
fi

# Cleanup
rm -f "$TMP_XML"
log_message "Cleanup complete"

exit 0