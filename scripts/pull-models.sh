#!/usr/bin/env bash
# =============================================================================
# Pull AI Models — Downloads recommended models for all services
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo ""
echo "============================================="
echo "  AI Model Downloader"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Ollama LLM Models
# ---------------------------------------------------------------------------
info "Pulling Ollama LLM models..."

OLLAMA_MODELS=(
    "llama3.1:8b"          # General purpose — best balance of speed/quality
    "mistral:7b"           # Fast, good for coding tasks
    "nomic-embed-text"     # Embedding model for RAG
)

for model in "${OLLAMA_MODELS[@]}"; do
    info "Pulling ${model}..."
    docker exec ollama ollama pull "${model}" && log "Downloaded ${model}" || warn "Failed to pull ${model}"
done

# ---------------------------------------------------------------------------
# 2. ComfyUI / Stable Diffusion Models
# ---------------------------------------------------------------------------
DATA_DIR="${HOME}/ai-data"
MODELS_DIR="${DATA_DIR}/comfyui/models"

info "Downloading Stable Diffusion models..."

# SDXL Base
SDXL_URL="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
SDXL_PATH="${MODELS_DIR}/checkpoints/sd_xl_base_1.0.safetensors"

if [ ! -f "${SDXL_PATH}" ]; then
    info "Downloading SDXL Base (6.9 GB)..."
    wget -q --show-progress -O "${SDXL_PATH}" "${SDXL_URL}" \
        && log "SDXL Base downloaded" \
        || warn "Failed to download SDXL Base. Download manually from HuggingFace."
else
    log "SDXL Base already exists"
fi

# SDXL VAE
VAE_URL="https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
VAE_PATH="${MODELS_DIR}/vae/sdxl_vae.safetensors"

if [ ! -f "${VAE_PATH}" ]; then
    info "Downloading SDXL VAE..."
    wget -q --show-progress -O "${VAE_PATH}" "${VAE_URL}" \
        && log "SDXL VAE downloaded" \
        || warn "Failed to download SDXL VAE"
else
    log "SDXL VAE already exists"
fi

echo ""
echo "============================================="
echo -e "${GREEN}  Model Downloads Complete${NC}"
echo "============================================="
echo ""
echo "  Ollama models: ${#OLLAMA_MODELS[@]} models pulled"
echo "  ComfyUI models: Check ${MODELS_DIR}/checkpoints/"
echo ""
echo "  Optional: Download more models from HuggingFace:"
echo "  - Flux:     huggingface.co/black-forest-labs/FLUX.1-dev"
echo "  - LoRAs:    civitai.com"
echo "  - More LLMs: ollama.com/library"
echo ""
