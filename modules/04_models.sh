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
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/models.yaml"

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
  while IFS=$'\t' read -r section url subdir; do
    var_name="$(echo "download_${section}" | tr '[:upper:]' '[:lower:]')"
    var_value="$(get_env "$var_name")"
    var_value="${var_value:-True}"
    if [ "$var_value" != "True" ]; then
      echo "[models] skipping due to ${var_name}=${var_value}: $url"
      continue
    fi

    if [[ "$url" =~ ^hf:// ]]; then
      spec="${url#hf://}"
      repo_id="${spec%%/*}"
      path="${spec#*/}"
      out="${MODELS_DIR}/${subdir}/$(basename "$path")"
      mkdir -p "$(dirname "$out")"
      download_hf_resolve "$repo_id" "$path" "$out"
    else
      fname="$(basename "$url")"
      out="${MODELS_DIR}/${subdir}/${fname}"
      mkdir -p "$(dirname "$out")"
      download_file "$url" "$out"
    fi
  done < <(python3 - "$CFG_FILE" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
for section, items in data.items():
    for item in items or []:
        url = item.get('url')
        target = item.get('target_dir', 'diffusion_models')
        print(f"{section}\t{url}\t{target}")
PY
  )
else
  cat <<EOF2
[models] missing ${CFG_FILE}.
Populate it with YAML sections, e.g.:

wan2.1:
  - url: hf://owner/repo/path/to/model.safetensors
    target_dir: diffusion_models

EOF2
fi

echo "[models] done."
