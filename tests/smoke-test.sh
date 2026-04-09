#!/usr/bin/env bash
# =============================================================================
# Smoke Test — Run AFTER deployment on the target VM
# Verifies all services are up, healthy, and reachable
# Usage: ./smoke-test.sh [--wait]
#   --wait : wait up to 5 min for services to become ready
# =============================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0; FAIL=0; WARN=0
ERRORS=()

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((FAIL++)); ERRORS+=("$*"); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARN++)); }
info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }

WAIT_MODE=false
[[ "${1:-}" == "--wait" ]] && WAIT_MODE=true

echo ""
echo "============================================="
echo "  AI Stack — Post-Deployment Smoke Test"
echo "============================================="
echo ""

# ---------------------------------------------------------------------------
# Wait for stack if requested
# ---------------------------------------------------------------------------
if $WAIT_MODE; then
    info "Waiting for services to start (up to 5 minutes)..."
    TIMEOUT=300
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if curl -sf http://localhost:11434/api/version > /dev/null 2>&1; then
            info "Ollama responded after ${ELAPSED}s"
            break
        fi
        sleep 5
        ((ELAPSED+=5))
    done
    if [ $ELAPSED -ge $TIMEOUT ]; then
        fail "Timeout waiting for Ollama to start"
    fi
fi

# ---------------------------------------------------------------------------
# 1. Container Status
# ---------------------------------------------------------------------------
echo "--- Container Status ---"

EXPECTED_CONTAINERS=("ollama" "open-webui" "comfyui" "triposr" "whisper" "piper" "caddy" "portainer" "watchtower")

for ctr in "${EXPECTED_CONTAINERS[@]}"; do
    STATUS=$(docker inspect -f '{{.State.Status}}' "$ctr" 2>/dev/null)
    if [ "$STATUS" = "running" ]; then
        pass "$ctr is running"
    elif [ -n "$STATUS" ]; then
        fail "$ctr status: $STATUS (expected: running)"
    else
        fail "$ctr container not found"
    fi
done

# ---------------------------------------------------------------------------
# 2. GPU Access
# ---------------------------------------------------------------------------
echo ""
echo "--- GPU Access ---"

# Check GPU from host
if nvidia-smi > /dev/null 2>&1; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader)
    pass "Host GPU: $GPU_NAME ($GPU_VRAM)"
else
    fail "nvidia-smi failed on host"
fi

# Check GPU from Ollama container
OLLAMA_GPU=$(docker exec ollama nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
if [ -n "$OLLAMA_GPU" ]; then
    pass "Ollama container GPU access: $OLLAMA_GPU"
else
    fail "Ollama container cannot access GPU"
fi

# ---------------------------------------------------------------------------
# 3. Service Health Endpoints
# ---------------------------------------------------------------------------
echo ""
echo "--- Service Endpoints ---"

# Ollama API
if curl -sf http://localhost:11434/api/version | jq -r .version > /dev/null 2>&1; then
    OLLAMA_VER=$(curl -sf http://localhost:11434/api/version | jq -r .version)
    pass "Ollama API responding (v${OLLAMA_VER})"
else
    fail "Ollama API not responding on :11434"
fi

# Open WebUI
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    pass "Open WebUI responding on :3000 (HTTP $HTTP_CODE)"
else
    fail "Open WebUI not responding on :3000 (HTTP $HTTP_CODE)"
fi

# ComfyUI
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8188 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    pass "ComfyUI responding on :8188"
else
    fail "ComfyUI not responding on :8188 (HTTP $HTTP_CODE)"
fi

# TripoSR
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8090 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    pass "TripoSR responding on :8090"
else
    fail "TripoSR not responding on :8090 (HTTP $HTTP_CODE)"
fi

# Whisper
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:10300 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
    pass "Whisper responding on :10300 (HTTP $HTTP_CODE)"
else
    fail "Whisper not responding on :10300 (HTTP $HTTP_CODE)"
fi

# Piper TTS
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:10200 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ]; then
    pass "Piper TTS responding on :10200 (HTTP $HTTP_CODE)"
else
    fail "Piper TTS not responding on :10200 (HTTP $HTTP_CODE)"
fi

# Caddy (HTTPS)
HTTP_CODE=$(curl -skf -o /dev/null -w "%{http_code}" https://localhost 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    pass "Caddy HTTPS proxy responding (HTTP $HTTP_CODE)"
else
    fail "Caddy HTTPS not responding (HTTP $HTTP_CODE)"
fi

# Health endpoint
HTTP_CODE=$(curl -skf -o /dev/null -w "%{http_code}" https://localhost/health 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    pass "Health endpoint OK"
else
    fail "Health endpoint not responding (HTTP $HTTP_CODE)"
fi

# Portainer
HTTP_CODE=$(curl -skf -o /dev/null -w "%{http_code}" https://localhost:9443 2>/dev/null)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
    pass "Portainer responding on :9443"
else
    fail "Portainer not responding on :9443 (HTTP $HTTP_CODE)"
fi

# ---------------------------------------------------------------------------
# 4. Inter-Service Connectivity
# ---------------------------------------------------------------------------
echo ""
echo "--- Inter-Service Connectivity ---"

# Open WebUI → Ollama
CONN=$(docker exec open-webui curl -sf http://ollama:11434/api/version 2>/dev/null)
if [ -n "$CONN" ]; then
    pass "Open WebUI → Ollama (internal network)"
else
    fail "Open WebUI cannot reach Ollama internally"
fi

# Caddy → Open WebUI
CONN=$(docker exec caddy wget -q -O- http://open-webui:8080 2>/dev/null | head -c 20)
if [ -n "$CONN" ]; then
    pass "Caddy → Open WebUI (internal network)"
else
    warn "Caddy → Open WebUI connectivity check inconclusive"
fi

# ---------------------------------------------------------------------------
# 5. LLM Model Check
# ---------------------------------------------------------------------------
echo ""
echo "--- LLM Models ---"

MODELS=$(docker exec ollama ollama list 2>/dev/null)
if [ -n "$MODELS" ]; then
    MODEL_COUNT=$(echo "$MODELS" | tail -n +2 | wc -l)
    if [ "$MODEL_COUNT" -gt 0 ]; then
        pass "Ollama has $MODEL_COUNT model(s) installed:"
        echo "$MODELS" | tail -n +2 | while read -r line; do
            info "  $line"
        done
    else
        warn "No models installed yet — run: docker exec ollama ollama pull llama3.1:8b"
    fi
else
    fail "Cannot list Ollama models"
fi

# ---------------------------------------------------------------------------
# 6. Docker Network
# ---------------------------------------------------------------------------
echo ""
echo "--- Docker Network ---"

NET_EXISTS=$(docker network inspect ai-net 2>/dev/null | jq length)
if [ "$NET_EXISTS" = "1" ]; then
    CONNECTED=$(docker network inspect ai-net 2>/dev/null | jq -r '.[0].Containers | keys | length')
    pass "ai-net network exists with $CONNECTED connected containers"
else
    fail "ai-net network does not exist"
fi

# ---------------------------------------------------------------------------
# 7. Disk & Memory
# ---------------------------------------------------------------------------
echo ""
echo "--- Resources ---"

DISK_AVAIL=$(df -h / | awk 'NR==2{print $4}')
info "Disk available: $DISK_AVAIL"

MEM_TOTAL=$(free -h | awk '/Mem:/{print $2}')
MEM_AVAIL=$(free -h | awk '/Mem:/{print $7}')
info "Memory: $MEM_AVAIL available of $MEM_TOTAL"

GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null)
GPU_MEM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null)
info "GPU VRAM: $GPU_MEM_USED used of $GPU_MEM_TOTAL"

# ---------------------------------------------------------------------------
# 8. Quick LLM inference test
# ---------------------------------------------------------------------------
echo ""
echo "--- Inference Test ---"

# Only test if a model is loaded
if docker exec ollama ollama list 2>/dev/null | tail -n +2 | grep -q .; then
    FIRST_MODEL=$(docker exec ollama ollama list 2>/dev/null | awk 'NR==2{print $1}')
    info "Testing inference with $FIRST_MODEL..."
    RESPONSE=$(docker exec ollama curl -sf http://localhost:11434/api/generate \
        -d "{\"model\":\"$FIRST_MODEL\",\"prompt\":\"Say hello in exactly 3 words.\",\"stream\":false}" \
        2>/dev/null | jq -r '.response' 2>/dev/null | head -c 100)
    if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "null" ]; then
        pass "LLM inference working: \"$RESPONSE\""
    else
        fail "LLM inference failed"
    fi
else
    warn "Skipping inference test — no models installed"
fi

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo "  SMOKE TEST SUMMARY"
echo "============================================="
echo ""
echo -e "  Passed:   ${GREEN}${PASS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARN}${NC}"
echo -e "  Failed:   $(if [ $FAIL -eq 0 ]; then echo "${GREEN}${FAIL}${NC}"; else echo "${RED}${FAIL}${NC}"; fi)"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "  ${RED}FAILURES:${NC}"
    for err in "${ERRORS[@]}"; do
        echo -e "    ${RED}- $err${NC}"
    done
    echo ""
fi

if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}ALL CHECKS PASSED — Stack is operational!${NC}"
else
    echo -e "  ${RED}$FAIL ISSUE(S) DETECTED — Review failures above${NC}"
fi
echo ""

exit $FAIL
