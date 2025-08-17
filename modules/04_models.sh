#!/usr/bin/env bash
set -euo pipefail

retry() {
  local n=0
  local max=5
  local delay=2
  while true; do
    "$@" && break
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      return 1
    fi
    echo "[retry] retry $n/$max: $*"
    sleep "$delay"
    delay=$((delay*2))
  done
}

WORKDIR="${WORKDIR:-/workspace}"
MODELS_DIR="${WORKDIR}/models"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/models.txt"

HF_TOKEN="${HF_TOKEN:-}"

get_env() {
  local name="$1"
  local val
  val="$(printenv "$name" 2>/dev/null || true)"
  echo "${val:-}"
}

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
  if command -v aria2c >/dev/null 2>&1; then
    # download using aria2c with 16 connections of 1MB each
    aria2c -x 16 -s 16 -k 1M -o "$(basename "$out")" -d "$(dirname "$out")" \
      --header="${auth_header[*]}" "$url" || \
      retry curl -L "${auth_header[@]}" -o "$out" "$url"
  else
    retry curl -L "${auth_header[@]}" -o "$out" "$url"
  fi
}

download_hf_resolve() {
  local repo_id="$1"
  local path="$2"
  local out="$3"
  if [ -z "$HF_TOKEN" ]; then
    echo "[models] HF_TOKEN missing; skip ${repo_id}/${path}" >&2
    return 0
  fi
  local base="https://huggingface.co"
  local mirror="https://hf-mirror.com"
  local url="${base}/${repo_id}/resolve/main/${path}"
  if ! download_file "$url" "$out"; then
    echo "[models] primary HuggingFace failed, trying mirror..."
    download_file "${mirror}/${repo_id}/resolve/main/${path}" "$out"
  fi
}

mkdir -p "${MODELS_DIR}/diffusion_models" \
         "${MODELS_DIR}/checkpoints" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/clip"

if [ -f "$CFG_FILE" ]; then
  echo "[models] reading list from ${CFG_FILE}"
  section=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^#[^#] ]]; then
      section="$(echo "$line" | sed -E 's/^#[[:space:]]*([^[:space:]]+).*/\1/')"
      continue
    fi
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    var_name="$(echo "download_${section}" | tr '[:upper:]' '[:lower:]')"
    var_value="$(get_env "$var_name")"
    var_value="${var_value:-True}"
    if [ "$var_value" != "True" ]; then
      echo "[models] skipping due to ${var_name}=${var_value}: $line"
      continue
    fi

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
