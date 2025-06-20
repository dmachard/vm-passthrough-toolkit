#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Load configuration
CONFIG_FILE="/etc/passthrough/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

info "Setting up hugepages configuration..."

# Create alloc_hugepages.sh
info "Creating hugepages allocation script..."
cp scripts/alloc_hugepages.sh /etc/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin/

# Create dealloc_hugepages.sh
info "Creating hugepages deallocation script..."
cp scripts/dealloc_hugepages.sh /etc/libvirt/hooks/qemu.d/$VM_NAME/release/end/

# Make scripts executable
chmod +x /etc/libvirt/hooks/qemu.d/$VM_NAME/prepare/begin/alloc_hugepages.sh
chmod +x /etc/libvirt/hooks/qemu.d/$VM_NAME/release/end/dealloc_hugepages.sh

info "Updating VM memory to ${VM_MEMORY}..."
# Create a temporary XML file
TEMP_XML=$(mktemp)
virsh dumpxml "$VM_NAME" > "$TEMP_XML"

# Update memory and currentMemory elements
MEMORY_KB=$((VM_MEMORY * 1024))
sed -i "s|<memory[^>]*>[0-9]*</memory>|<memory unit='KiB'>$MEMORY_KB</memory>|" "$TEMP_XML"
sed -i "s|<currentMemory[^>]*>[0-9]*</currentMemory>|<currentMemory unit='KiB'>$MEMORY_KB</currentMemory>|" "$TEMP_XML"

success "Memory updated to ${VM_MEMORY} (${MEMORY_KB} KB)"

# Add hugepages to VM configuration
info "Adding hugepages to VM configuration..."
if ! virsh dumpxml "$VM_NAME" | grep -q "<hugepages/>"; then
    # Add hugepages configuration after currentMemory
    sed -i '/<currentMemory.*>/a \  <memoryBacking>\n    <hugepages/>\n  </memoryBacking>' "$TEMP_XML"

    success "Hugepages configuration added to VM"
else
    info "Hugepages already configured in VM"
fi

# Apply the configuration if XML was modified
if [[ -f "${TEMP_XML:-}" ]]; then
    info "Applying VM configuration changes..."
    virsh define "$TEMP_XML" >> "$LOGFILE" 2>&1
    rm "$TEMP_XML"
    success "VM configuration updated successfully"
fi