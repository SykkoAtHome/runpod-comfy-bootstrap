#!/usr/bin/env bash
set -euo pipefail

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

# link ComfyUI models directory directly to workspace/models to avoid duplicates
rm -rf "${COMFY_DIR}/models"
ln -sfn "${WORKDIR}/models" "${COMFY_DIR}/models"

# link input/output to ComfyUI for convenience
ln -sfn "${WORKDIR}/input"  "${COMFY_DIR}/input"
ln -sfn "${WORKDIR}/output" "${COMFY_DIR}/output"

echo "[workspace] models linked to /workspace/models (no extra_model_paths.yaml)"
echo "[workspace] done."

