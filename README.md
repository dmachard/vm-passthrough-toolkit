# 🧰 VM Passthrough Toolkit

Automated Setup to enable GPU and gamepad passthrough on a Ubuntu/Debian-based Linux distribution host
to virtual machines (QEMU/KVM) using [Looking Glass](https://looking-glass.io/) and VFIO and technology.
Ideal for gaming VM setups.

## ✨ Features

- 🎮 **Gamepad Passthrough**
- 🖥️ **GPU Passthrough**

## 🚀 Quick Start

```bash
git clone https://github.com/dmachard/vm-passthrough-toolkit
cd vm-passthrough-toolkit
```

The main configuration file is `/etc/passthrough/config.conf`:

**Configure your VM name** in `/etc/passthrough/config.conf`
**Start your VM**: `virsh start YourVMName`

```bash
# Main VM for gamepad attachment
VM_NAME=Windows10

# Log file location (optional)
LOGFILE=/tmp/passthrough.log
```

Run install

```bash
./setup.sh --all         # Install all
./setup.sh --gpu         # Install only GPU module
./setup.sh --gamepad     # Install only gamepad module
```


3. Reboot your system

4. Once rebooted, run the setup again to verify everything is in place:

```bash
sudo ./setup.sh
```


## Toolkit description

The script will:
1. Detect your hardware configuration
    - **CPU Virtualization Check**: Verifies that VT-x/VT-d (Intel) or AMD-V/AMD-Vi (AMD) is enabled
    - **IOMMU Support**: Checks for IOMMU capability and configuration
    - **RAM Validation**: Ensures sufficient memory (16GB+ recommended)
2. Present available GPUs and audio controllers
    - **Multi-GPU Detection**: Identifies all available GPUs and their PCI addresses
    - **Audio Controller Detection**: Finds audio devices that can be passed through alongside GPUs
3. Allow you to select which devices to pass through
4. Install all required packages and dependencies
    - **QEMU/KVM**: Installs virtualization platform
    - **Libvirt**: Configures virtual machine management
    - **Virt-Manager**: Provides GUI for VM creation and management
5. Configure GRUB, VFIO, and kernel modules
    - **GRUB Bootloader**: Configures kernel parameters for IOMMU and VFIO
    - **VFIO Driver Setup**: Binds selected GPU/audio devices to VFIO-PCI driver
    - **Driver Blacklisting**: Prevents host system from using passthrough devices
    - **Kernel Module Configuration**: Sets up required modules for virtualization
6. Build and install Looking Glass
    - **Kernel Module**: Installs kvmfr module for shared memory communication
    - **Client Application**: Builds and installs the Looking Glass client from source
    - **Device Permissions**: Configures proper access rights for the kvmfr device
    - **Shared Memory**: Sets up 128MB shared memory buffer for video transmission

This will check that:
- Selected GPU is using the vfio-pci driver
- Audio devices are properly configured
- Looking Glass device (`/dev/kvmfr0`) is available
- Looking Glass client is installed and accessible

## Troubleshooting


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
