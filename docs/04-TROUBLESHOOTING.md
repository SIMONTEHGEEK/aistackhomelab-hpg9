# Troubleshooting

## Container Won't Start

```bash
# Check logs for a specific container
docker compose logs <service-name> --tail 100

# Check if GPU is available
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

# Restart the entire stack
cd ~/ai-stack/docker && docker compose down && docker compose up -d
```

## Ollama Issues

### Model won't load — out of memory

```bash
# Check current VRAM usage
nvidia-smi

# Kill any lingering GPU processes
sudo fuser -v /dev/nvidia*

# Use a smaller model
docker exec ollama ollama pull qwen3.5:9b
```

### Ollama API not responding

```bash
# Check if container is healthy
docker ps | grep ollama

# Restart just Ollama
docker compose restart ollama

# Check Ollama logs
docker compose logs ollama --tail 50
```

## Open WebUI Issues

### "Connection refused" to Ollama

The Open WebUI container must be able to reach Ollama at `http://ollama:11434`. Check:

```bash
# Test connectivity from Open WebUI container
docker exec open-webui curl -s http://ollama:11434/api/version
```

If it fails, both containers must be on the same Docker network (handled by docker-compose).

### Voice not working

1. **STT (Whisper)**: Check Faster-Whisper container is running and accessible
2. **TTS (Piper)**: Check Piper container is running
3. **Browser**: Ensure HTTPS is used (microphone requires secure context)
4. **Permissions**: Allow microphone access in browser

## ComfyUI Issues

### Models not loading

Models must be placed in the correct directory:

```
~/ai-data/comfyui/models/
├── checkpoints/          # Main models (SDXL, Flux)
├── loras/                # LoRA models
├── controlnet/           # ControlNet models
├── vae/                  # VAE models
└── clip/                 # CLIP models
```

### CUDA out of memory during generation

- Close other GPU services: `docker compose stop ollama`
- Use lower resolution or fewer steps
- Try SDXL Turbo for faster, lower-VRAM generation

## TripoSR Issues

### Poor 3D quality

- Input image should have: clean background, single object, good lighting
- Pre-process images with background removal before feeding to TripoSR
- Output mesh may need cleanup in Blender/MeshLab

## Network / Traefik Issues

### Can't access web interfaces

```bash
# Check Traefik is running
docker compose logs traefik

# Verify ports are open
sudo ss -tlnp | grep -E '80|443|9443'

# Test locally
curl -k https://localhost
```

### Self-signed certificate warnings

Traefik auto-generates a default self-signed certificate. For local network access without warnings:
- Export Traefik's default cert and import into your browser/OS trust store
- Or configure a real domain with Let's Encrypt ACME in traefik.yml

## Performance Tips

1. **Keep Ollama model resident**: Set `OLLAMA_KEEP_ALIVE=24h` if you mostly chat
2. **Use quantized models**: Q4_K_M offers best quality/VRAM tradeoff
3. **SSD matters**: Model loading speed depends heavily on disk I/O (you have NVMe, you're good)
4. **Monitor with `nvtop`**: Real-time GPU monitoring
5. **Set GPU power limit** if thermals are an issue:
   ```bash
   sudo nvidia-smi -pl 200  # Limit to 200W (default is 230W)
   ```

## Full Reset

If everything is broken and you want to start fresh:

```bash
cd ~/ai-stack/docker
docker compose down -v          # Stop all + remove volumes (DATA LOSS)
docker system prune -af         # Clean up everything
docker compose up -d            # Fresh start
```

> **Warning**: This deletes all data including chat history and downloaded models.
