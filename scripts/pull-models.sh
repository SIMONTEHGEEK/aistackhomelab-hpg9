#!/usr/bin/env bash
# =============================================================================
# Pull AI Models — Downloads recommended models for all services
# Updated: April 2026
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

DATA_DIR="${HOME}/ai-data"
MODELS_DIR="${DATA_DIR}/comfyui/models"

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
    "qwen3.5:9b"           # Primary — vision + thinking + tools, best all-rounder
    "qwen3:14b"            # Stronger reasoning when you need it (no vision)
    "nomic-embed-text"     # Embedding model for RAG / document search
)

for model in "${OLLAMA_MODELS[@]}"; do
    info "Pulling ${model}..."
    docker exec ollama ollama pull "${model}" && log "Downloaded ${model}" || warn "Failed to pull ${model}"
done

# ---------------------------------------------------------------------------
# 2. ComfyUI / Stable Diffusion Models
# ---------------------------------------------------------------------------
info "Downloading image generation models..."

download_model() {
    local url="$1"
    local path="$2"
    local name="$3"
    local size="$4"

    if [ -f "${path}" ]; then
        log "${name} already exists"
        return 0
    fi

    info "Downloading ${name} (${size})..."
    wget -q --show-progress -O "${path}" "${url}" \
        && log "${name} downloaded" \
        || warn "Failed to download ${name}"
}

# --- SDXL Base (best balance of quality and VRAM on A5000) ---
download_model \
    "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
    "${MODELS_DIR}/checkpoints/sd_xl_base_1.0.safetensors" \
    "SDXL 1.0 Base" "6.9 GB"

# --- SDXL Turbo (real-time generation, 1-4 steps, lower quality but instant) ---
download_model \
    "https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors" \
    "${MODELS_DIR}/checkpoints/sd_xl_turbo_1.0_fp16.safetensors" \
    "SDXL Turbo (fast, 1-step)" "3.3 GB"

# --- SDXL VAE (improved VAE for SDXL) ---
download_model \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
    "${MODELS_DIR}/vae/sdxl_vae.safetensors" \
    "SDXL VAE" "335 MB"

# --- FLUX.1 Schnell (Apache 2.0, highest quality, 1-4 steps, needs ~12 GB VRAM) ---
# NOTE: Requires HuggingFace login — download manually if this fails
download_model \
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/flux1-schnell.safetensors" \
    "${MODELS_DIR}/checkpoints/flux1-schnell.safetensors" \
    "FLUX.1 Schnell (highest quality)" "23 GB"

# --- FLUX VAE ---
download_model \
    "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors" \
    "${MODELS_DIR}/vae/flux_ae.safetensors" \
    "FLUX VAE" "335 MB"

# --- CLIP models for FLUX ---
mkdir -p "${MODELS_DIR}/clip"
download_model \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
    "${MODELS_DIR}/clip/clip_l.safetensors" \
    "CLIP-L (for FLUX)" "246 MB"

download_model \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors" \
    "${MODELS_DIR}/clip/t5xxl_fp8_e4m3fn.safetensors" \
    "T5-XXL FP8 (for FLUX)" "4.9 GB"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo -e "${GREEN}  Model Downloads Complete${NC}"
echo "============================================="
echo ""
echo "  LLM models:"
echo "    qwen3.5:9b     — Vision + thinking + tools (primary)"
echo "    qwen3:14b      — Stronger reasoning (secondary)"
echo "    nomic-embed     — RAG embeddings"
echo ""
echo "  Image generation models:"
echo "    SDXL 1.0        — Best balance (~8 GB VRAM)"
echo "    SDXL Turbo      — Instant generation (~4 GB VRAM)"
echo "    FLUX.1 Schnell  — Highest quality (~16 GB VRAM, LLM must unload)"
echo ""
echo "  Models dir: ${MODELS_DIR}/"
echo ""
echo "  Note: FLUX and SD 3.5 may require HuggingFace login."
echo "  If downloads fail, visit huggingface.co, accept the license,"
echo "  and use: huggingface-cli download <model> --local-dir <path>"
echo ""
