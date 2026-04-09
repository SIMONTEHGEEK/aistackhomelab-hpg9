# AI Home Server Stack — HP DL380 G9

## Hardware Specification

| Component | Detail |
|-----------|--------|
| Server | HP ProLiant DL380 Gen9 |
| CPU | Intel Xeon E5-2600 v3/v4 series |
| RAM | 128 GB DDR4 ECC |
| Storage | 13 TB Samsung PCIe NVMe (Enterprise) |
| GPU | NVIDIA RTX A5000 (24 GB GDDR6) |
| Hypervisor | Proxmox VE (IOMMU passthrough configured) |

## Stack Overview

| Service | Purpose | Port | GPU VRAM (weights + KV cache/working mem) |
|---------|---------|------|-------------------------------------------|
| **Ollama** | LLM inference engine | 11434 | 7–20 GB (model + context dependent) |
| **Open WebUI** | Chat UI + Voice + RAG | 3000 | — |
| **ComfyUI** | Image generation (SDXL/Flux) | 8188 | 8–18 GB |
| **Faster-Whisper** | Speech-to-Text | 10300 | ~2 GB |
| **Piper TTS** | Text-to-Speech | 10200 | CPU only |
| **Traefik** | Reverse proxy + auto TLS | 80/443 | — |
| **Portainer** | Docker management GUI | 9443 | — |
| **Watchtower** | Auto container updates | — | — |

## VRAM Budget (24 GB RTX A5000)

The A5000 has 24 GB VRAM. Figures below include model weights **plus** KV cache,
context window buffers, and working memory (not just weights alone):

- **Ollama** (always loaded): ~7 GB idle / ~10 GB active (8B Q4_K_M model, 8K context)
  - Weights: ~4.7 GB, KV cache at 8K ctx: ~2 GB, CUDA overhead: ~0.5 GB
  - At 32K context: add ~6 GB KV cache → ~13 GB total
  - 13B Q4_K_M: ~7.4 GB weights + ~3 GB KV cache = ~12 GB at 8K ctx
- **ComfyUI** (on-demand): SDXL ~8 GB / Flux ~16 GB
  - SDXL: ~3.5 GB weights + ~2 GB VAE/CLIP + ~2.5 GB sampling workspace
  - Flux Dev: ~12 GB weights + ~4 GB working memory
- **Faster-Whisper** (lightweight): ~2 GB
  - large-v3: ~1.5 GB weights + ~0.5 GB CTranslate2 buffers

**Strategy**: Ollama stays resident. ComfyUI claims VRAM on-demand.
Use `OLLAMA_MAX_LOADED_MODELS=1` and `OLLAMA_KEEP_ALIVE=5m` to auto-unload idle models.

**Important**: You CANNOT run Ollama (8B) + Flux simultaneously — they exceed 24 GB
together. Use SDXL for image gen while keeping the LLM loaded, or let Ollama unload first.

## Quick Start

```bash
# 1. Create the VM in Proxmox (see docs/01-VM-SETUP.md)

# 2. SSH into the VM and clone this repo
git clone <this-repo> ~/ai-stack && cd ~/ai-stack

# 3. Run the bootstrap script
chmod +x scripts/bootstrap.sh
sudo ./scripts/bootstrap.sh

# 4. Deploy the stack
cd docker && docker compose up -d

# 5. Pull your first LLM model
docker exec ollama ollama pull qwen3.5:9b

# 6. Access services
# Chat:      https://<your-ip>/
# ComfyUI:   https://<your-ip>/comfy
# Portainer: https://<your-ip>:9443
```

## Project Structure

```
AIINIT/
├── README.md                    # This file
├── docs/
│   ├── 01-VM-SETUP.md          # Proxmox VM creation guide
│   ├── 02-GPU-PASSTHROUGH.md   # GPU passthrough verification
│   ├── 03-STACK-GUIDE.md       # Full stack walkthrough
│   └── 04-TROUBLESHOOTING.md   # Common issues & fixes
├── docker/
│   ├── docker-compose.yml      # Main orchestration file
│   ├── traefik.yml              # Traefik static config
│   ├── dynamic/                 # Traefik dynamic config (middleware)
│   └── .env                    # Environment variables
├── scripts/
│   ├── bootstrap.sh            # Full VM bootstrap (drivers, docker, etc.)
│   ├── pull-models.sh          # Download AI models
│   └── backup.sh               # Backup script for configs & data
└── configs/
    └── open-webui/             # Open WebUI custom configs
```
