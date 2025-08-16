#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
COMFY_DIR="${WORKDIR}/ComfyUI"
NODES_DIR="${COMFY_DIR}/custom_nodes"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/custom_nodes.txt"

# ComfyUI repository
if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[nodes] cloning ComfyUI..."
  git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
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
pip install --upgrade pip wheel setuptools
pip install -r "${COMFY_DIR}/requirements.txt" || true
for req in "${NODES_DIR}"/*/requirements.txt; do
  [ -f "$req" ] && pip install -r "$req" || true
done

# optional: start ComfyUI here
# nohup python "${COMFY_DIR}/main.py" --listen 0.0.0.0 --port 8188 > "${WORKDIR}/logs/comfyui.log" 2>&1 &

