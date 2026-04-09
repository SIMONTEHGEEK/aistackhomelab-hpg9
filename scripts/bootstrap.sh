#!/usr/bin/env bash
# =============================================================================
# AI Stack Bootstrap Script
# Installs: NVIDIA drivers, Docker, NVIDIA Container Toolkit, and prerequisites
# Target: Ubuntu 24.04 LTS VM with RTX A5000 passthrough
# =============================================================================
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

# Must run as root
[[ $EUID -eq 0 ]] || err "This script must be run as root (use sudo)"

DATA_DIR="/home/${SUDO_USER:-$USER}/ai-data"
STACK_DIR="/home/${SUDO_USER:-$USER}/ai-stack"

echo ""
echo "============================================="
echo "  AI Stack Bootstrap — HP DL380 G9 + A5000"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# 1. System Update
# ---------------------------------------------------------------------------
info "Step 1/7: Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git htop nvtop net-tools \
    build-essential pkg-config \
    ca-certificates gnupg lsb-release \
    software-properties-common \
    unzip jq
log "System packages updated"

# ---------------------------------------------------------------------------
# 2. Blacklist Nouveau
# ---------------------------------------------------------------------------
info "Step 2/7: Blacklisting Nouveau driver..."
if lsmod | grep -q nouveau; then
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    update-initramfs -u
    warn "Nouveau was loaded. A reboot is required. Re-run this script after reboot."
    warn "Rebooting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    reboot
fi
log "Nouveau driver not loaded (good)"

# ---------------------------------------------------------------------------
# 3. Install NVIDIA Driver
# ---------------------------------------------------------------------------
info "Step 3/7: Installing NVIDIA driver..."
if command -v nvidia-smi &> /dev/null; then
    log "NVIDIA driver already installed: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
else
    # Add NVIDIA package repository
    apt-get install -y -qq linux-headers-$(uname -r)
    
    # Use Ubuntu's built-in NVIDIA driver packages
    add-apt-repository -y ppa:graphics-drivers/ppa
    apt-get update -qq
    
    # Install the latest tested driver (550+ series)
    DRIVER_VERSION=$(apt-cache search nvidia-driver | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1)
    apt-get install -y -qq "nvidia-driver-${DRIVER_VERSION}" nvidia-utils-${DRIVER_VERSION}
    
    log "NVIDIA driver ${DRIVER_VERSION} installed"
    warn "A reboot is required for the driver to load. Re-run this script after reboot."
    warn "Rebooting in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    reboot
fi

# Verify GPU
nvidia-smi > /dev/null 2>&1 || err "nvidia-smi failed. GPU may not be properly passed through."
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader)
log "GPU detected: ${GPU_NAME} (${GPU_VRAM})"

# ---------------------------------------------------------------------------
# 4. Install Docker
# ---------------------------------------------------------------------------
info "Step 4/7: Installing Docker..."
if command -v docker &> /dev/null; then
    log "Docker already installed: $(docker --version)"
else
    # Official Docker install
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    usermod -aG docker "${SUDO_USER:-$USER}"
    
    log "Docker installed"
fi

# ---------------------------------------------------------------------------
# 5. Install NVIDIA Container Toolkit
# ---------------------------------------------------------------------------
info "Step 5/7: Installing NVIDIA Container Toolkit..."
if dpkg -l | grep -q nvidia-container-toolkit; then
    log "NVIDIA Container Toolkit already installed"
else
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update -qq
    apt-get install -y -qq nvidia-container-toolkit
    
    # Configure Docker to use NVIDIA runtime
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    
    log "NVIDIA Container Toolkit installed and configured"
fi

# Verify GPU in Docker
info "Verifying GPU access in Docker..."
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi > /dev/null 2>&1 \
    && log "GPU accessible in Docker containers" \
    || err "GPU not accessible in Docker. Check NVIDIA Container Toolkit installation."

# ---------------------------------------------------------------------------
# 6. Create Directory Structure
# ---------------------------------------------------------------------------
info "Step 6/7: Creating data directories..."
ACTUAL_USER="${SUDO_USER:-$USER}"

mkdir -p "${DATA_DIR}"/{ollama,open-webui,comfyui/{models/checkpoints,models/loras,models/controlnet,models/vae,models/clip,output,input,custom_nodes},triposr/{input,output},whisper,piper,traefik/certs,portainer}

chown -R "${ACTUAL_USER}:${ACTUAL_USER}" "${DATA_DIR}"

log "Data directories created at ${DATA_DIR}"

# ---------------------------------------------------------------------------
# 7. Set System Tuning
# ---------------------------------------------------------------------------
info "Step 7/7: Applying system optimizations..."

# Increase inotify watches for file-heavy AI workloads
if ! grep -q "fs.inotify.max_user_watches" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf << 'EOF'

# AI Stack optimizations
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
vm.swappiness=10
EOF
    sysctl -p
fi

# Enable NVIDIA persistence mode (keeps GPU initialized)
nvidia-smi -pm 1 2>/dev/null || true

log "System optimizations applied"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo -e "${GREEN}  Bootstrap Complete!${NC}"
echo "============================================="
echo ""
echo "  GPU: ${GPU_NAME} (${GPU_VRAM})"
echo "  Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
echo "  Data dir: ${DATA_DIR}"
echo ""
echo "  Next steps:"
echo "  1. Log out and back in (for docker group)"
echo "  2. cd ${STACK_DIR}/docker"
echo "  3. docker compose up -d"
echo "  4. Run: ${STACK_DIR}/scripts/pull-models.sh"
echo ""
