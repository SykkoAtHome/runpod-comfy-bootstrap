#!/usr/bin/env bash

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
COMFY_DIR="${WORKDIR}/ComfyUI"
NODES_DIR="${COMFY_DIR}/custom_nodes"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/custom_nodes.txt"

if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[nodes] ComfyUI not found in ${COMFY_DIR}, skipping custom nodes"
  exit 0
fi

# ComfyUI-Manager
if [ ! -d "${NODES_DIR}/ComfyUI-Manager/.git" ]; then
  echo "[nodes] installing ComfyUI-Manager..."
  retry git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "${NODES_DIR}/ComfyUI-Manager" || true
else
  retry git -C "${NODES_DIR}/ComfyUI-Manager" pull --rebase || true
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
      retry git clone --depth 1 "$repo" "$dest" || true
    else
      echo "[nodes] update: $name"
      retry git -C "$dest" pull --rebase || true
    fi
  done < "$CFG_FILE"
else
  echo "[nodes] missing ${CFG_FILE}. Add Git repositories (one per line)."
fi

# requirements
echo "[nodes] installing Python dependencies..."
reqs=()
[ -f "${COMFY_DIR}/requirements.txt" ] && reqs+=("-r" "${COMFY_DIR}/requirements.txt")
for req in "${NODES_DIR}"/*/requirements.txt; do
  [ -f "$req" ] && reqs+=("-r" "$req")
done
if [ "${#reqs[@]}" -gt 0 ]; then
  python3 -m pip install "${reqs[@]}" || true
fi

# optional dependencies for certain plugins
if [ -d "${NODES_DIR}/ComfyUI-Impact-Pack" ]; then
  python3 -m pip install sageattention || true
fi
if [ -d "${NODES_DIR}/ComfyUI-Easy-Use" ]; then
  python3 -m pip install onnxruntime-gpu || python3 -m pip install onnxruntime || true
fi
