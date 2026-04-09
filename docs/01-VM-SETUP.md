# VM Setup — Proxmox VE

## VM Specifications

Create a new VM in Proxmox with the following settings:

| Setting | Value | Rationale |
|---------|-------|-----------|
| **VM ID** | 200 | Convention: 2xx = AI workloads |
| **Name** | `ai-server` | |
| **OS** | Ubuntu 24.04.x LTS (Server) | Long-term support, wide driver compatibility |
| **CPU** | 16 vCPUs, type: `host` | `host` type required for full instruction set passthrough |
| **RAM** | 96 GB (96000 MB) | Leaves 32 GB for Proxmox + other VMs |
| **Ballooning** | Disabled | AI workloads need consistent memory |
| **BIOS** | OVMF (UEFI) | Required for GPU passthrough |
| **Machine** | q35 | Required for PCIe passthrough |
| **SCSI Controller** | VirtIO SCSI Single | Best performance |
| **Disk** | 500 GB on NVMe, `discard=on`, `iothread=1` | Fast I/O for model loading |
| **Network** | VirtIO, bridge `vmbr0` | Full-speed networking |

## Step-by-Step in Proxmox GUI

### 1. Download Ubuntu ISO

```bash
# On the Proxmox host
cd /var/lib/vz/template/iso/
wget https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso
```

### 2. Create VM via GUI

1. **General**: VM ID `200`, Name `ai-server`
2. **OS**: Select the Ubuntu 24.04 ISO, Guest OS type `Linux`, Version `6.x - 2.6 Kernel`
3. **System**:
   - BIOS: `OVMF (UEFI)`
   - Machine: `q35`
   - Add EFI Disk (on same storage)
   - Uncheck "Pre-Enroll keys" (avoids Secure Boot issues with NVIDIA)
4. **Disks**: VirtIO Block, 500 GB, enable `Discard`, enable `IO Thread`
5. **CPU**: 16 cores, Type `host`
6. **Memory**: 96000 MB, uncheck `Ballooning Device`
7. **Network**: VirtIO, bridge `vmbr0`

### 3. Add GPU Passthrough

After VM creation, add the PCI device:

```bash
# On Proxmox host — find GPU PCI address
lspci -nn | grep -i nvidia
# Example output: 3b:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA102GL [RTX A5000] [10de:2231]
# Note: also grab the audio device (usually 3b:00.1)
```

Edit the VM config directly:

```bash
nano /etc/pve/qemu-server/200.conf
```

Add these lines:

```
hostpci0: 3b:00,pcie=1,x-vga=0
cpu: host
machine: q35
```

> Replace `3b:00` with your actual PCI address. Use the short form to passthrough
> both the GPU and its audio function.

### 4. Proxmox Host — Blacklist NVIDIA on Host

Ensure the Proxmox host does NOT load NVIDIA drivers:

```bash
# /etc/modprobe.d/blacklist-nvidia.conf
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm
blacklist nvidia_modeset

# /etc/modprobe.d/vfio.conf  
options vfio-pci ids=10de:2231,10de:1aef
```

> Replace the PCI IDs with your actual GPU device IDs from `lspci -nn`.

```bash
update-initramfs -u -k all
reboot
```

### 5. Install Ubuntu

1. Start the VM
2. Walk through the Ubuntu Server installer
3. **Disk**: Use entire disk (the 500 GB VirtIO drive)
4. **User**: Create user `admin` (or your preference)
5. **SSH**: Enable OpenSSH server during install
6. **Reboot** after installation

### 6. Post-Install Basics

SSH into the VM:

```bash
ssh admin@<vm-ip>

# Update system
sudo apt update && sudo apt upgrade -y

# Install essentials
sudo apt install -y curl wget git htop nvtop net-tools

# Verify GPU is visible
lspci | grep -i nvidia
# Should show the RTX A5000
```

If the GPU shows up, proceed to the bootstrap script (`scripts/bootstrap.sh`) which handles everything else.

## VM Resource Allocation Summary

```
Proxmox Host Total:  128 GB RAM  |  All CPU cores  |  13 TB NVMe
─────────────────────────────────────────────────────────────────
ai-server VM:         96 GB RAM  |  16 vCPUs       |  500 GB disk
Remaining:            32 GB RAM  |  remaining cores |  ~12.5 TB free
```
