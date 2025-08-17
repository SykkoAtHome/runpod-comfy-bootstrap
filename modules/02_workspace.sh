#!/usr/bin/env bash

WORKDIR="${WORKDIR:-/workspace}"

# locate or create ComfyUI directory
CANDIDATES=("${WORKDIR}/ComfyUI" "/workspace/ComfyUI" "/opt/ComfyUI")
COMFY_DIR=""
for c in "${CANDIDATES[@]}"; do
  if [ -d "$c" ]; then COMFY_DIR="$c"; break; fi
done
[ -z "$COMFY_DIR" ] && COMFY_DIR="${WORKDIR}/ComfyUI" && mkdir -p "${COMFY_DIR}"

echo "[workspace] COMFY_DIR = ${COMFY_DIR}"
# ensure common directories
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

# link ComfyUI models directory directly to workspace/models to avoid duplicates
safe_link "${WORKDIR}/models" "${COMFY_DIR}/models"

# link input/output to ComfyUI for convenience
safe_link "${WORKDIR}/input"  "${COMFY_DIR}/input"
safe_link "${WORKDIR}/output" "${COMFY_DIR}/output"

echo "[workspace] done."

