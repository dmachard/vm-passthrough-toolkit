#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Load configuration
CONFIG_FILE="/etc/passthrough/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

info "Setting up BIOS/sysinfo passthrough for VM '$VM_NAME'..."

# Check dmidecode is available
if ! command -v dmidecode &>/dev/null; then
  error "Error: dmidecode is required but not found."
fi

# Gather system info
bios_vendor=$(dmidecode -s bios-vendor)
bios_version=$(dmidecode -s bios-version)
bios_date=$(dmidecode -s bios-release-date)
bios_release=$(dmidecode -s bios-revision)

system_manufacturer=$(dmidecode -s system-manufacturer)
system_product=$(dmidecode -s system-product-name)
system_version=$(dmidecode -s system-version)
system_serial=$(dmidecode -s system-serial-number)
system_uuid=$(dmidecode -s system-uuid)
system_sku=$(dmidecode -s system-sku-number)
system_family=$(dmidecode -s system-family)

baseboard_manufacturer=$(dmidecode -s baseboard-manufacturer)
baseboard_product=$(dmidecode -s baseboard-product-name)
baseboard_version=$(dmidecode -s baseboard-version)
baseboard_serial=$(dmidecode -s baseboard-serial-number)
baseboard_asset=$(dmidecode -s baseboard-asset-tag)

# Build the sysinfo XML block
SYSINFO_XML=$(cat <<EOF
  <sysinfo type="smbios">
    <bios>
      <entry name="vendor">${bios_vendor}</entry>
      <entry name="version">${bios_version}</entry>
      <entry name="date">${bios_date}</entry>
      <entry name="release">${bios_release}</entry>
    </bios>
    <system>
      <entry name="manufacturer">${system_manufacturer}</entry>
      <entry name="product">${system_product}</entry>
      <entry name="version">${system_version}</entry>
      <entry name="serial">${system_serial}</entry>
      <entry name="uuid">${system_uuid}</entry>
      <entry name="sku">${system_sku}</entry>
      <entry name="family">${system_family}</entry>
    </system>
    <baseBoard>
      <entry name="manufacturer">${baseboard_manufacturer}</entry>
      <entry name="product">${baseboard_product}</entry>
      <entry name="version">${baseboard_version}</entry>
      <entry name="serial">${baseboard_serial}</entry>
      <entry name="asset">${baseboard_asset}</entry>
    </baseBoard>
  </sysinfo>
EOF
)

# Temporary file for VM XML
TEMP_XML=$(mktemp)

# Dump current VM XML
virsh dumpxml "$VM_NAME" > "$TEMP_XML"

# Remove existing <sysinfo> block if any
sed -i '/<sysinfo/,/<\/sysinfo>/d' "$TEMP_XML"

# Remplacer l'UUID de la VM par celui de l'hôte
sed -i "s|<uuid>.*</uuid>|<uuid>${system_uuid}</uuid>|" "$TEMP_XML"

# Insert sysinfo block after <vcpu ...> element
SYSINFO_TEMP=$(mktemp)
echo "$SYSINFO_XML" > "$SYSINFO_TEMP"
sed -i "/<vcpu.*>/r $SYSINFO_TEMP" "$TEMP_XML"
rm "$SYSINFO_TEMP"

info "Updating VM XML configuration..."

# Apply new configuration
virsh undefine "$VM_NAME"
virsh define "$TEMP_XML"

rm "$TEMP_XML"

info "VM $VM_NAME updated with SMBIOS sysinfo."
