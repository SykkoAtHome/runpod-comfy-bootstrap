#!/usr/bin/env bash

WORKDIR="${WORKDIR:-/workspace}"

TOTAL_STEPS=3
STEP=1

log_step() {
  local msg="$1"
  echo "[workspace] [$STEP/$TOTAL_STEPS] $msg"
}

# locate or create ComfyUI directory
log_step "locating ComfyUI directory"
CANDIDATES=("${WORKDIR}/ComfyUI" "/workspace/ComfyUI" "/opt/ComfyUI")
COMFY_DIR=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then COMFY_DIR="$c"; break; fi
done
[ -z "$COMFY_DIR" ] && COMFY_DIR="${WORKDIR}/ComfyUI" && mkdir -p "${COMFY_DIR}"
echo "[workspace] COMFY_DIR = ${COMFY_DIR}"

STEP=$((STEP+1))
log_step "ensuring common directories"
mkdir -p "${WORKDIR}/input" "${WORKDIR}/output" "${WORKDIR}/workflows" "${WORKDIR}/logs" "${WORKDIR}/models"

safe_link() {
  local target="$1"
  local link="$2"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "[workspace] exists and not a symlink, leaving: $link"
  else
    ln -sfn "$target" "$link"
    echo "[workspace] link: $link -> $target"
  fi
}

# link directories
STEP=$((STEP+1))
log_step "creating symlinks"
# link ComfyUI models directory directly to workspace/models to avoid duplicates
safe_link "${WORKDIR}/models" "${COMFY_DIR}/models"

# link input/output to ComfyUI for convenience
safe_link "${WORKDIR}/input"  "${COMFY_DIR}/input"
safe_link "${WORKDIR}/output" "${COMFY_DIR}/output"

echo "[workspace] done."

