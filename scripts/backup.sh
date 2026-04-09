#!/usr/bin/env bash
# =============================================================================
# Backup Script — Backs up configs, chat history, and metadata
# Does NOT backup model weights (they can be re-downloaded)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[i]${NC} $*"; }

DATA_DIR="${HOME}/ai-data"
BACKUP_DIR="${HOME}/ai-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/ai-stack-backup-${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

info "Starting backup..."

# Backup configs and user data (exclude large model files)
tar -czf "${BACKUP_FILE}" \
    --exclude='*.safetensors' \
    --exclude='*.bin' \
    --exclude='*.gguf' \
    --exclude='*.pt' \
    --exclude='*.pth' \
    --exclude='*.onnx' \
    --exclude='comfyui/output/*' \
    --exclude='triposr/output/*' \
    -C "${HOME}" \
    ai-data/open-webui \
    ai-data/caddy \
    ai-data/portainer \
    ai-data/piper \
    ai-stack/docker \
    2>/dev/null || true

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
log "Backup created: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Keep only last 7 backups
info "Cleaning old backups (keeping last 7)..."
ls -t "${BACKUP_DIR}"/ai-stack-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm --
log "Backup complete"
