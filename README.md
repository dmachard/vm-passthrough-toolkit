# VM Passthrough Toolkit

A toolkit to automate GPU and gamepad passthrough setup on Ubuntu/Debian-based systems using [Looking Glass](https://looking-glass.io/), VFIO, and QEMU/KVM virtualization.  
Ideal for gaming virtual machines.

## ✨ Features

- 🖥️ **GPU Passthrough** with HDMI dummy plug
- ⚙️ **CPU Pinning** for performance optimization
- 🎮 **Gamepad Passthrough** via VFIO
- 🧠 **Memory Tuning** with Hugepages
- 🧬 **BIOS Passthrough** with vendor-specific tweaks
- **Disk** (tbc)

## 🚀 Quick Start

```bash
git clone https://github.com/dmachard/vm-passthrough-toolkit
cd vm-passthrough-toolkit
```

**Configure your VM name** in `./config/config.conf`

```bash
# Main VM for gamepad attachment
VM_NAME=Windows10

# Log file location (optional)
LOGFILE=/tmp/passthrough.log
```

Run install

```bash
./setup.sh --all         # Install all modules (GPU, CPU pinning, gamepad, hugepages, BIOS tweaks)
./setup.sh --gpu         # Install GPU passthrough support
./setup.sh --cpu         # Configure CPU pinning for the VM
./setup.sh --gamepad     # Install gamepad passthrough (VFIO or network)
./setup.sh --hugepages   # Enable hugepages for memory optimization
./setup.sh --bios        # Apply BIOS passthrough and UEFI/OVMF tweaks
```

3. Reboot your system

4. Once rebooted, run the setup again to verify everything is in place:

```bash
sudo ./setup.sh --all
```

## 🛠️ Toolkit Overview

The toolkit performs the following:
- Hardware Detection
    - **CPU Virtualization Check**: Verifies that VT-x/VT-d (Intel) or AMD-V/AMD-Vi (AMD) is enabled
    - **IOMMU Support**: Checks for IOMMU capability and configuration
    - **RAM Validation**: Ensures sufficient memory (16GB+ recommended)
- GPU & Audio Detection
    - **Multi-GPU Detection**: Identifies all available GPUs and their PCI addresses
    - **Audio Controller Detection**: Finds audio devices that can be passed through alongside GPUs
- Dependency Installation
    - **QEMU/KVM**: Installs virtualization platform
    - **Libvirt**: Configures virtual machine management
    - **Virt-Manager**: Provides GUI for VM creation and management
- Configure GRUB, VFIO, and kernel modules
    - **GRUB Bootloader**: Configures kernel parameters for IOMMU and VFIO
    - **VFIO Driver Setup**: Binds selected GPU/audio devices to VFIO-PCI driver
    - **Driver Blacklisting**: Prevents host system from using passthrough devices
    - **Kernel Module Configuration**: Sets up required modules for virtualization
- Build and install Looking Glass
    - **Kernel Module**: Installs kvmfr module for shared memory communication
    - **Client Application**: Builds and installs the Looking Glass client from source
    - **Device Permissions**: Configures proper access rights for the kvmfr device
    - **Shared Memory**: Sets up 128MB shared memory buffer for video transmission

## 🧩 Troubleshooting

Installation logs

```bash
# Check script logs
tail -f /tmp/passthrough.log
```

Monitor Gamepad Detection

```bash
# Watch for gamepad events
sudo udevadm monitor --environment --udev

# Check system logs
journalctl -f -t gamepad-vm
```

# VM Tuning

- Autologon
- Disable UAC