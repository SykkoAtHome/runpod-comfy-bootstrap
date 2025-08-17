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

repos=()
if [ -f "$CFG_FILE" ]; then
  mapfile -t repos < <(grep -vE '^\s*$|^\s*#' "$CFG_FILE")
fi
TOTAL_STEPS=$(( ${#repos[@]} + 2 ))
STEP=1

log_step() {
  local msg="$1"
  echo "[nodes] [$STEP/$TOTAL_STEPS] $msg"
}

if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[nodes] ComfyUI not found in ${COMFY_DIR}, skipping custom nodes"
  exit 0
fi

# ComfyUI-Manager
log_step "installing ComfyUI-Manager"
if [ ! -d "${NODES_DIR}/ComfyUI-Manager/.git" ]; then
  retry git clone --progress --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git "${NODES_DIR}/ComfyUI-Manager" || true
else
  retry git -C "${NODES_DIR}/ComfyUI-Manager" pull --progress --rebase || true
fi
STEP=$((STEP+1))

# additional nodes from config
if [ ${#repos[@]} -gt 0 ]; then
  echo "[nodes] reading list from ${CFG_FILE}"
  for repo in "${repos[@]}"; do
    log_step "processing ${repo}"
    name="$(basename "$repo" .git)"
    dest="${NODES_DIR}/${name}"
    if [ ! -d "${dest}/.git" ]; then
      retry git clone --progress --depth 1 "$repo" "$dest" || true
    else
      retry git -C "$dest" pull --progress --rebase || true
    fi
    STEP=$((STEP+1))
  done
else
  echo "[nodes] missing ${CFG_FILE}. Add Git repositories (one per line)."
fi

# requirements
log_step "installing Python dependencies"
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
