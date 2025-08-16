#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
COMFY_DIR="${WORKDIR}/ComfyUI"
NODES_DIR="${COMFY_DIR}/custom_nodes"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/custom_nodes.txt"

if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[nodes] ComfyUI not found in ${COMFY_DIR}" >&2
  exit 1
fi

# ComfyUI-Manager
if [ ! -d "${NODES_DIR}/ComfyUI-Manager/.git" ]; then
  echo "[nodes] installing ComfyUI-Manager..."
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git "${NODES_DIR}/ComfyUI-Manager"
else
  (cd "${NODES_DIR}/ComfyUI-Manager" && git pull --rebase || true)
fi

# additional nodes from config
if [ -f "$CFG_FILE" ]; then
  echo "[nodes] reading list from ${CFG_FILE}"
  while IFS= read -r repo; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    name="$(basename "$repo" .git)"
    dest="${NODES_DIR}/${name}"
    if [ ! -d "${dest}/.git" ]; then
      echo "[nodes] clone: $repo"
      git clone "$repo" "$dest" || true
    else
      echo "[nodes] update: $name"
      (cd "$dest" && git pull --rebase || true)
    fi
  done < "$CFG_FILE"
else
  echo "[nodes] missing ${CFG_FILE}. Add Git repositories (one per line)."
fi

# requirements
echo "[nodes] installing Python dependencies..."
python3 -m pip install --upgrade pip wheel setuptools
python3 -m pip install -r "${COMFY_DIR}/requirements.txt" || true
for req in "${NODES_DIR}"/*/requirements.txt; do
  [ -f "$req" ] && python3 -m pip install -r "$req" || true
done
