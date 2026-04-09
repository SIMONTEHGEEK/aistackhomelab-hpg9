# Full Stack Guide

## Architecture

All services run as Docker containers orchestrated by Docker Compose.
A Caddy reverse proxy provides HTTPS and path-based routing.

## Service Details

### 1. Ollama — LLM Inference Engine

- **What**: Runs open-source LLMs locally (Llama 3.1, Mistral, Phi-3, Qwen2, etc.)
- **Why**: Simple API, automatic VRAM management, supports hot-swapping models
- **VRAM**: 7–20 GB total (weights + KV cache + CUDA overhead)
- **Recommended models** (VRAM = weights + KV cache at 8K context):
  - `llama3.1:8b` — Best general-purpose (~10 GB total: 4.7 GB weights + 2 GB KV + overhead)
  - `llama3.1:70b-q4` — Won't fit in 24 GB with context — use `llama3.1:8b` instead
  - `mistral:7b` — Fast, good at coding (~8 GB total)
  - `phi3:14b` — Microsoft, great reasoning (~14 GB total)
  - `qwen2.5:14b` — Strong multilingual (~14 GB total)

### 2. Open WebUI — Chat Interface

- **What**: Full-featured web UI for chatting with LLMs
- **Why**: Supports voice input/output natively, RAG (document upload), multi-model, image generation integration
- **Features used**:
  - Chat with any Ollama model
  - Voice input via Faster-Whisper (STT)
  - Voice output via Piper (TTS)
  - Image generation via ComfyUI integration
  - Document/PDF upload for RAG
  - Conversation history & user management

### 3. ComfyUI — Image Generation

- **What**: Node-based Stable Diffusion interface
- **Why**: Most flexible image gen tool, supports SDXL, Flux, ControlNet, LoRA
- **VRAM**: 8–18 GB total (weights + VAE + CLIP + sampling buffers)
- **Models to download**:
  - `sd_xl_base_1.0.safetensors` — Stable Diffusion XL base (~8 GB total VRAM)
  - `flux1-dev.safetensors` — Black Forest Labs Flux (~16 GB total — requires Ollama to unload)
  - Various LoRAs and ControlNet models as needed

### 4. TripoSR — 3D Model Generation

- **What**: Generates 3D meshes from single images in seconds
- **Why**: State-of-the-art single-image-to-3D, fast inference
- **VRAM**: ~5 GB total (~1 GB weights + ~3–4 GB mesh generation working memory)
- **Output**: OBJ/GLB mesh files viewable in browser
- **Alternative**: InstantMesh (higher quality but slower)

### 5. Faster-Whisper — Speech-to-Text

- **What**: Optimized OpenAI Whisper implementation using CTranslate2
- **Why**: 4x faster than original Whisper, lower VRAM usage
- **Model**: `large-v3` for best accuracy (~2 GB VRAM: 1.5 GB weights + 0.5 GB buffers)
- **Integration**: Connected to Open WebUI for voice chat

### 6. Piper TTS — Text-to-Speech

- **What**: Fast local neural text-to-speech
- **Why**: Runs on CPU, low latency, many voice options
- **Integration**: Connected to Open WebUI for voice responses

### 7. Caddy — Reverse Proxy

- **What**: Modern web server with automatic HTTPS
- **Why**: Zero-config TLS, simple configuration, HTTP/2
- **Routes**:
  - `/` → Open WebUI (chat)
  - `/comfy/*` → ComfyUI
  - `/3d/*` → TripoSR
  - `:9443` → Portainer

### 8. Portainer — Docker Management

- **What**: Web GUI for managing Docker containers
- **Why**: Easy monitoring, logs, restart containers without SSH

### 9. Watchtower — Auto Updates

- **What**: Monitors and auto-updates Docker containers
- **Why**: Keeps stack current without manual intervention
- **Schedule**: Checks daily at 4 AM

## Network Topology

```
Internet (optional)
       │
    Router
       │
    ┌──┴──────────────────┐
    │  Home Network        │
    │  192.168.x.0/24      │
    │                      │
    │  ┌────────────────┐  │
    │  │ ai-server VM   │  │
    │  │ 192.168.x.xxx  │  │
    │  │                │  │
    │  │ :443  → Caddy  │  │
    │  │ :9443 → Portnr │  │
    │  └────────────────┘  │
    └──────────────────────┘
```

## Data Persistence

All data is stored in Docker volumes mapped to host directories:

| Path | Contents | Size Estimate |
|------|----------|---------------|
| `~/ai-data/ollama/` | LLM model weights | 20–100 GB |
| `~/ai-data/open-webui/` | Chat history, user data, uploads | 1–10 GB |
| `~/ai-data/comfyui/models/` | SD models, LoRAs, ControlNets | 20–200 GB |
| `~/ai-data/comfyui/output/` | Generated images | Variable |
| `~/ai-data/triposr/` | 3D model outputs | Variable |
| `~/ai-data/whisper/` | Whisper model cache | ~3 GB |
| `~/ai-data/piper/` | TTS voice models | ~1 GB |
| `~/ai-data/caddy/` | TLS certs, config | <1 MB |
| `~/ai-data/portainer/` | Portainer data | <100 MB |

**Total estimated storage**: 50–300 GB (well within the 500 GB VM disk)

## GPU VRAM Sharing Strategy

The RTX A5000 has 24 GB VRAM. Services share it dynamically.
All figures include model weights **plus** KV cache, context buffers, and working memory.

**Normal chatbot usage** (~12 GB):
- Ollama (8B Q4_K_M, 8K context): ~10 GB (4.7 GB weights + 2 GB KV + overhead)
- Faster-Whisper: ~2 GB

**Image generation with SDXL** (~18 GB peak, fits alongside idle LLM):
- Ollama (idle, model resident): ~7 GB
- ComfyUI SDXL pipeline: ~8 GB (weights + VAE + CLIP + sampling)
- Faster-Whisper: ~2 GB
- Total: ~17 GB — fits within 24 GB

**Image generation with Flux** (~16 GB, LLM must unload):
- Ollama auto-unloads after 5m idle
- ComfyUI Flux pipeline: ~16 GB
- Total: ~16 GB + Whisper ~2 GB = ~18 GB

**3D generation** (~7 GB):
- TripoSR: ~5 GB
- Faster-Whisper: ~2 GB
- Can run alongside 8B LLM (~10 GB) → ~17 GB total

**What does NOT fit simultaneously**:
- Ollama (8B active) + Flux = ~10 + 16 = 26 GB — exceeds 24 GB
- Ollama (14B active) + SDXL = ~14 + 8 = 22 GB — tight, may OOM with long context

Ollama is configured with `OLLAMA_MAX_LOADED_MODELS=1` and `OLLAMA_KEEP_ALIVE=5m` to
automatically free VRAM when idle, making room for image/3D generation.
