#!/usr/bin/env bash
set -euo pipefail

# =========[ MODUŁ 04: MODELE ]=========
WORKDIR="${WORKDIR:-/workspace}"
MODELS_DIR="${WORKDIR}/models"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/models.txt"

HF_TOKEN="${HF_TOKEN:-}"   # dodaj w RunPod → Environment Variables, jeśli używasz gated modeli

auth_header=()
if [ -n "$HF_TOKEN" ]; then
  auth_header=(-H "Authorization: Bearer ${HF_TOKEN}")
fi

download_file () {
  local url="$1"
  local out="$2"
  if [ -f "$out" ]; then
    echo "[models] istnieje: $out"
    return 0
  fi
  echo "[models] pobieram: $url"
  curl -L "${auth_header[@]}" -o "$out" "$url"
}

download_hf_resolve () {
  local repo_id="$1"   # np. Comfy-Org/Wan_2.1_ComfyUI_repackaged
  local path="$2"      # np. split_files/diffusion_models/wan2.1.safetensors
  local out="$3"
  local url="https://huggingface.co/${repo_id}/resolve/main/${path}"
  download_file "$url" "$out"
}

# Przykładowe katalogi (dopasuj do potrzeb)
mkdir -p "${MODELS_DIR}/diffusion_models" \
         "${MODELS_DIR}/checkpoints" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/clip"

if [ -f "$CFG_FILE" ]; then
  echo "[models] czytam listę z ${CFG_FILE}"
  # Format linii (dowolny z poniższych):
  # 1) bezpośredni URL:
  #    https://serwer.com/sciezka/do/model.safetensors -> diffusion_models
  # 2) hf-resolve (repo_id::path_w_repo::subdir_docelowy):
  #    hf://Comfy-Org/Wan_2.1_ComfyUI_repackaged::split_files/diffusion_models/wan2.1.safetensors::diffusion_models
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    if [[ "$line" =~ ^hf:// ]]; then
      # hf://repo_id::path::subdir
      spec="${line#hf://}"
      repo_id="${spec%%::*}"; rest="${spec#*::}"
      path="${rest%%::*}"; subdir="${rest#*::}"
      out="${MODELS_DIR}/${subdir}/$(basename "$path")"
      download_hf_resolve "$repo_id" "$path" "$out"
    else
      # traktujemy jako URL bezpośredni; domyślnie zapis do diffusion_models
      fname="$(basename "$line")"
      out="${MODELS_DIR}/diffusion_models/${fname}"
      download_file "$line" "$out"
    fi
  done < "$CFG_FILE"
else
  cat <<EOF
[models] Brak pliku ${CFG_FILE}.
Dodaj modele w jednym z formatów (po jednej pozycji na linię), np.:

# Bezpośredni URL:
https://example.com/path/to/phantom.safetensors

# Hugging Face (resolve):
hf://Comfy-Org/Wan_2.1_ComfyUI_repackaged::split_files/diffusion_models/wan2.1.safetensors::diffusion_models
hf://WAN-Labs/VACE::vace14b.safetensors::diffusion_models
EOF
fi

echo "[models] gotowe."
# =========[ /MODUŁ 04 ]=========
