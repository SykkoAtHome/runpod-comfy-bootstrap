#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
MODELS_DIR="${WORKDIR}/models"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/models.txt"

HF_TOKEN="${HF_TOKEN:-}"  # set in RunPod env vars for gated models

auth_header=()
if [ -n "$HF_TOKEN" ]; then
  auth_header=(-H "Authorization: Bearer ${HF_TOKEN}")
fi

download_file() {
  local url="$1"
  local out="$2"
  if [ -f "$out" ]; then
    echo "[models] exists: $out"
    return 0
  fi
  echo "[models] downloading: $url"
  curl -L "${auth_header[@]}" -o "$out" "$url"
}

download_hf_resolve() {
  local repo_id="$1"   # e.g. Comfy-Org/Wan_2.1_ComfyUI_repackaged
  local path="$2"      # e.g. split_files/diffusion_models/wan2.1.safetensors
  local out="$3"
  local url="https://huggingface.co/${repo_id}/resolve/main/${path}"
  download_file "$url" "$out"
}

mkdir -p "${MODELS_DIR}/diffusion_models" \
         "${MODELS_DIR}/checkpoints" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/clip"

if [ -f "$CFG_FILE" ]; then
  echo "[models] reading list from ${CFG_FILE}"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^hf:// ]]; then
      spec="${line#hf://}"
      repo_id="${spec%%::*}"; rest="${spec#*::}"
      path="${rest%%::*}"; subdir="${rest#*::}"
      out="${MODELS_DIR}/${subdir}/$(basename "$path")"
      download_hf_resolve "$repo_id" "$path" "$out"
    else
      fname="$(basename "$line")"
      out="${MODELS_DIR}/diffusion_models/${fname}"
      download_file "$line" "$out"
    fi
  done < "$CFG_FILE"
else
  cat <<EOF2
[models] missing ${CFG_FILE}.
Add models in one of the formats below (one per line), e.g.:

# direct URL
https://example.com/path/to/phantom.safetensors

# Hugging Face (resolve)
hf://Comfy-Org/Wan_2.1_ComfyUI_repackaged::split_files/diffusion_models/wan2.1.safetensors::diffusion_models
hf://WAN-Labs/VACE::vace14b.safetensors::diffusion_models
EOF2
fi

echo "[models] done."

