# GPU Passthrough Verification

## Inside the VM — Verify GPU Access

### 1. Check PCI Device

```bash
lspci | grep -i nvidia
```

Expected output:
```
01:00.0 VGA compatible controller: NVIDIA Corporation GA102GL [RTX A5000] (rev a1)
01:00.1 Audio device: NVIDIA Corporation GA102 High Definition Audio Controller (rev a1)
```

### 2. After Driver Installation — Verify NVIDIA Driver

```bash
nvidia-smi
```

Expected output:
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 550.xx       Driver Version: 550.xx       CUDA Version: 12.x    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  NVIDIA RTX A5000    Off  | 00000000:01:00.0 Off |                  Off |
| 30%   35C    P8    22W / 230W |      0MiB / 24564MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
```

Key things to verify:
- [x] GPU name shows "RTX A5000"
- [x] 24564 MiB (24 GB) VRAM available
- [x] Driver version 550+
- [x] CUDA version 12.x

### 3. Verify Docker GPU Access

After Docker + NVIDIA Container Toolkit install:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

This should show the same `nvidia-smi` output inside a container.

### 4. Benchmark GPU

Quick CUDA test:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 \
  bash -c "apt-get update && apt-get install -y cuda-samples-12-4 && \
  cd /usr/local/cuda/samples/1_Utilities/deviceQuery && make && ./deviceQuery"
```

## Troubleshooting GPU Passthrough

### GPU not visible in VM (`lspci` shows nothing)

1. Verify IOMMU is enabled on Proxmox host:
   ```bash
   dmesg | grep -e DMAR -e IOMMU
   ```
2. Verify the VM config has `hostpci0` set correctly
3. Ensure machine type is `q35` and BIOS is `OVMF`

### NVIDIA driver install fails

1. Disable Nouveau first:
   ```bash
   sudo bash -c "echo 'blacklist nouveau' >> /etc/modprobe.d/blacklist-nouveau.conf"
   sudo bash -c "echo 'options nouveau modeset=0' >> /etc/modprobe.d/blacklist-nouveau.conf"
   sudo update-initramfs -u
   sudo reboot
   ```
2. Then install driver from the bootstrap script

### `nvidia-smi` shows "No devices were found"

- Check VM config: ensure `pcie=1` is set in hostpci0
- Try adding `args: -cpu host,kvm=off` to VM config (bypasses NVIDIA VM detection)

### Docker `--gpus all` fails

1. Verify NVIDIA Container Toolkit is installed:
   ```bash
   dpkg -l | grep nvidia-container-toolkit
   ```
2. Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```
3. Check the runtime config:
   ```bash
   cat /etc/docker/daemon.json
   ```
   Should contain:
   ```json
   {
     "runtimes": {
       "nvidia": {
         "path": "nvidia-container-runtime",
         "runtimeArgs": []
       }
     }
   }
   ```
