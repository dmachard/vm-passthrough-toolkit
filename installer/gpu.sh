#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/passthrough/config.conf"
DEFAULT_LOGFILE="/tmp/passthrough_setup.log"
DEFAULT_STATE_FILE="/tmp/passthrough_setup.state"

# Check if running as root
# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from $CONFIG_FILE" >> "$DEFAULT_LOGFILE"
    source "$CONFIG_FILE"
fi

# Set defaults if not configured
VM_NAME="${VM_NAME:-$DEFAULT_VM}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOGFILE}"
STATE_FILE="${STATE_FILE:-$DEFAULT_STATE_FILE}"

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    
    printf "\r["
    printf "%*s" $completed | tr ' ' '='
    printf "%*s" $((width - completed)) | tr ' ' '-'
    printf "] %d%% (%d/%d)" $percentage $current $total
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script should be run as root. Use sudo."
    fi
}

# Hardware detection functions
detect_cpu_vendor() {
    local vendor=$(lscpu | awk -F: '/Vendor ID/ {gsub(/ /,"",$2); print $2; exit}')
    case $vendor in
        "GenuineIntel")
            echo "intel"
            ;;
        "AuthenticAMD")
            echo "amd"
            ;;
        *)
            error "Unknown CPU vendor: $vendor"
            ;;
    esac
}

check_virtualization() {
    info "Checking virtualization support..."

    if ! lscpu | grep -q "Virtualization"; then
        error "Virtualization not enabled in BIOS. Please enable VT-x/VT-d (Intel) or AMD-V/AMD-Vi (AMD)"
    fi

    local virt_type=$(lscpu | grep "Virtualization" | awk '{print $2}')
    success "Virtualization enabled: $virt_type"
}

check_iommu() {
    info "Checking IOMMU support..."

    if [ -d /sys/kernel/iommu_groups ] || \
       dmesg | grep -Eiq 'iommu|dmar|amd-vi|ivrs'; then
        success "IOMMU is enabled and active"
    else
        info "IOMMU may not be enabled. It will be configured in GRUB."
    fi
}

detect_gpus() {
    info "Detecting GPUs..."

    local gpu_count=0
    declare -g -A GPUS

    while IFS= read -r line; do
        if [[ $line =~ ([0-9a-f]{2}:[0-9a-f]{2}\.[0-9]).*\[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
            local pci_addr="${BASH_REMATCH[1]}"
            local vendor_id="${BASH_REMATCH[2]}"
            local device_id="${BASH_REMATCH[3]}"
            local description=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

            GPUS["$gpu_count,pci"]="$pci_addr"
            GPUS["$gpu_count,vendor"]="$vendor_id"
            GPUS["$gpu_count,device"]="$device_id"
            GPUS["$gpu_count,desc"]="$description"

            info "GPU $gpu_count: $pci_addr - $description [$vendor_id:$device_id]"
            gpu_count=$((gpu_count + 1))
        fi
    done < <(lspci -nn | grep -i vga)

    if [[ $gpu_count -lt 2 ]]; then
        error "At least 2 GPUs required for passthrough. Found: $gpu_count"
    fi

    success "Found $gpu_count GPUs"
    declare -g GPU_COUNT=$gpu_count
}

detect_audio_controllers() {
    info "Detecting audio controllers..."

    local audio_count=0
    declare -g -A AUDIO_DEVICES

    while IFS= read -r line; do
        if [[ $line =~ ([0-9a-f]{2}:[0-9a-f]{2}\.[0-9]).*\[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
            local pci_addr="${BASH_REMATCH[1]}"
            local vendor_id="${BASH_REMATCH[2]}"
            local device_id="${BASH_REMATCH[3]}"
            local description=$(echo "$line" | cut -d':' -f3- | sed 's/^ *//')

            AUDIO_DEVICES["$audio_count,pci"]="$pci_addr"
            AUDIO_DEVICES["$audio_count,vendor"]="$vendor_id"
            AUDIO_DEVICES["$audio_count,device"]="$device_id"
            AUDIO_DEVICES["$audio_count,desc"]="$description"

            info "Audio $audio_count: $pci_addr - $description [$vendor_id:$device_id]"
            audio_count=$((audio_count + 1))
        fi
    done < <(lspci -nn | grep -i audio)

    declare -g AUDIO_COUNT=$audio_count
    success "Found $audio_count audio controllers"
}

# User selection functions
select_passthrough_gpu() {
    info "Select GPU for passthrough to VM:"

    for ((i=0; i<GPU_COUNT; i++)); do
        echo "  $i) ${GPUS[$i,desc]} [${GPUS[$i,vendor]}:${GPUS[$i,device]}]"
    done

    while true; do
        read -p "Enter GPU number for passthrough: " gpu_choice
        if [[ $gpu_choice =~ ^[0-9]+$ ]] && [[ $gpu_choice -lt $GPU_COUNT ]]; then
            declare -g PASSTHROUGH_GPU=$gpu_choice
            success "Selected GPU: ${GPUS[$gpu_choice,desc]}"
            break
        else
            warning "Invalid selection. Please enter a number between 0 and $((GPU_COUNT-1))"
        fi
    done
}

select_passthrough_audio() {
    if [[ $AUDIO_COUNT -eq 0 ]]; then
        warning "No audio controllers found"
        return
    fi

    info "Select audio controller for passthrough (or skip):"

    for ((i=0; i<AUDIO_COUNT; i++)); do
        echo "  $i) ${AUDIO_DEVICES[$i,desc]} [${AUDIO_DEVICES[$i,vendor]}:${AUDIO_DEVICES[$i,device]}]"
    done

    while true; do
        read -p "Enter audio controller number: " audio_choice
        if [[ $audio_choice =~ ^[0-9]+$ ]] && [[ $audio_choice -lt $AUDIO_COUNT ]]; then
            declare -g PASSTHROUGH_AUDIO=$audio_choice
            success "Selected Audio: ${AUDIO_DEVICES[$audio_choice,desc]}"
            break
        else
            warning "Invalid selection. Please enter a number between 0 and $((AUDIO_COUNT-1)) or 's'"
        fi
    done
}

install_dependencies() {
    info "Installing required packages..."
    
    local packages=(
        # Virtu
        "qemu-kvm"
        "virt-manager"
        "bridge-utils"
        "virt-viewer"

        # Compilation / build
        "linux-headers-$(uname -r)"
        "dkms"
        "build-essential"
        "gcc"
        "g++"
        "cmake"
        "binutils-dev"
        "pkg-config"

        # Polices
        "fonts-dejavu-core"
        "libfontconfig-dev"

        # OpenGL / EGL / GLES
        "libegl-dev"
        "libgl-dev"
        "libgles-dev"

        # Wayland & X11
        "libx11-dev"
        "libxcursor-dev"
        "libxi-dev"
        "libxinerama-dev"
        "libxpresent-dev"
        "libxss-dev"
        "libxkbcommon-dev"
        "libwayland-dev"
        "wayland-protocols"
        "libxcb-shm0-dev"
	"libxcb-xfixes0-dev"

        # audio
        "libpipewire-0.3-dev"
        "libpulse-dev"
        "libsamplerate0-dev"

        # misc
        "libspice-protocol-dev"
        "nettle-dev"
    )
    
    for ((i=0; i<${#packages[@]}; i++)); do
        show_progress $((i+1)) ${#packages[@]}
        sudo apt-get install -y "${packages[$i]}" >> "$LOG_FILE" 2>&1
    done
    echo # New line after progress bar
    
    success "All packages installed"
}

configure_libvirt() {
    info "Configuring libvirt..."
    
    systemctl enable libvirtd.service
    systemctl start libvirtd.service
    usermod -aG libvirt "$SUDO_USER"
    
    success "Libvirt configured."
}

configure_grub() {
    info "Configuring GRUB for IOMMU and VFIO..."

    # Backup current GRUB config
    sudo cp /etc/default/grub "/etc/default/grub.backup"

    local cpu_vendor=$(detect_cpu_vendor) || exit 1
    local iommu_param

    if [[ $cpu_vendor == "intel" ]]; then
        iommu_param="intel_iommu=on"
    else
        iommu_param="amd_iommu=on"
    fi

    # Build device IDs string
    local device_ids="${GPUS[$PASSTHROUGH_GPU,vendor]}:${GPUS[$PASSTHROUGH_GPU,device]}"
    if [[ -n $PASSTHROUGH_AUDIO ]]; then
        device_ids+=",${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,vendor]}:${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,device]}"
    fi

    # Update GRUB configuration
    local grub_cmdline="quiet splash $iommu_param iommu=pt vfio-pci.ids=$device_ids"

    sudo sed -i.bak "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$grub_cmdline\"/" /etc/default/grub

    sudo grub-mkconfig -o /boot/grub/grub.cfg

    success "GRUB configured with: $grub_cmdline"
}

configure_vfio() {
    info "Configuring VFIO..."
    
    # VFIO configuration
    local device_ids="${GPUS[$PASSTHROUGH_GPU,vendor]}:${GPUS[$PASSTHROUGH_GPU,device]}"
    if [[ -n $PASSTHROUGH_AUDIO ]]; then
        device_ids+=",${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,vendor]}:${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,device]}"
    fi
    
    echo "options vfio-pci ids=$device_ids" | sudo tee /etc/modprobe.d/vfio.conf
    
    # Blacklist GPU drivers
    sudo tee /etc/modprobe.d/blacklist-gpu.conf > /dev/null <<EOF
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist rivafb
blacklist nvidia_drm
blacklist nvidia_uvm
blacklist nvidia_modeset
blacklist amdgpu
blacklist radeon
EOF
    
    sudo update-initramfs -c -k "$(uname -r)"
    
    success "VFIO configured for devices: $device_ids"
}

install_looking_glass() {
    info "Installing Looking Glass..."

    local lg_version="B7"
    local lg_url="https://looking-glass.io/artifact/$lg_version/source"
    local lg_dir="/tmp/looking-glass-$lg_version"

    # Download and extract
    cd /tmp
    if [[ ! -f "looking-glass-$lg_version.tar.gz" ]]; then
        wget -O "looking-glass-$lg_version.tar.gz" "$lg_url"
    fi

    if [[ -d "$lg_dir" ]]; then
        rm -rf "$lg_dir"
    fi

    tar -xzf "looking-glass-$lg_version.tar.gz"
    cd "$lg_dir"

    # Install kernel module
    info "Installing Looking Glass kernel module..."
    cd module
    dkms install .
    cd ..

    # Configure kvmfr
    echo "options kvmfr static_size_mb=128" | tee /etc/modprobe.d/kvmfr.conf
    echo "kvmfr" | tee /etc/modules-load.d/kvmfr.conf

    # Create udev rule
    echo "SUBSYSTEM==\"kvmfr\", OWNER=\"$SUDO_USER\", GROUP=\"kvm\", MODE=\"0660\"" | tee /etc/udev/rules.d/99-kvmfr.rules

    # Build client
    info "Building Looking Glass client..."
    mkdir -p client/build
    cd client/build

    info "Running CMake..."
    cmake .. >> "$LOG_FILE" 2>&1 || error "CMake configuration failed. See $LOG_FILE"

    info "Compiling..."
    make -j"$(nproc)" >> "$LOG_FILE" 2>&1 || error "Build failed. See $LOG_FILE"

    info "Installing..."
    sudo make install >> "$LOG_FILE" 2>&1 || error "Installation failed. See $LOG_FILE"

    success "Looking Glass installed"
}

verify_setup() {
    info "1. Verify GPU isolation:"
    if ! lspci -k | grep -A 3 -E 'VGA|3D' | grep -B 3 vfio-pci > /dev/null; then
        info "No GPUs currently using vfio-pci."
    else
        lspci -k | grep -A 3 -E 'VGA|3D' | grep -B 3 vfio-pci
    fi

    info "2. Audio devices using vfio-pci driver:"
    if ! lspci -k | grep -A 3 -E 'Audio' | grep -B 3 vfio-pci > /dev/null; then
        info "No audio devices currently using vfio-pci."
    else
        lspci -k | grep -A 3 -E 'Audio' | grep -B 3 vfio-pci
    fi

    info "3. Check Looking Glass device node:"
    if [ -e /dev/kvmfr0 ]; then
        ls -l /dev/kvmfr0
        info "Looking Glass device /dev/kvmfr0 exists."
    else
        error "Looking Glass device /dev/kvmfr0 not found. Is the kvmfr module loaded?"
    fi

    info "4. Verify Looking Glass client installation:"
    if command -v looking-glass-client >/dev/null 2>&1; then
        info "Looking Glass client is installed."
    else
        error "Looking Glass client is not installed or not in PATH."
    fi
}

# Main setup function
main() {
    check_root

    if [[ ! -f $STATE_FILE ]]; then

    	check_virtualization
    	check_iommu
    	detect_gpus
    	detect_audio_controllers

    	info "Please select hardware for passthrough:"
    	select_passthrough_gpu
    	select_passthrough_audio

    	info "Setup will configure:"
    	info "  - GPU: ${GPUS[$PASSTHROUGH_GPU,desc]}"
        info "  - Audio: ${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,desc]}"

    	info "Starting installation..."
    	install_dependencies
    	configure_libvirt
    	configure_grub
    	configure_vfio
    	install_looking_glass

	sudo rm -f "$STATE_FILE"
	echo "PASSTHROUGH_GPU=${GPUS[$PASSTHROUGH_GPU,desc]}" > "$STATE_FILE"
	echo "PASSTHROUGH_AUDIO=${AUDIO_DEVICES[$PASSTHROUGH_AUDIO,desc]}" >> "$STATE_FILE"

    	info "Initial setup complete. A system reboot is required to apply GRUB and VFIO changes."
    	echo -e "\n${YELLOW}Please reboot your system now. After reboot, re-run this script for next steps.${NC}"
    
    else
        info "Checking setup..."
        verify_setup
	sudo rm -f "$STATE_FILE"
    fi
}

# Trap errors
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
