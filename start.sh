#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[bootstrap] błąd w linii $LINENO"; exit 1' ERR

WORKDIR="${WORKDIR:-/workspace}"
REPO_DIR="${REPO_DIR:-${WORKDIR}/runpod-comfy-bootstrap}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

export PIP_EXTRA_INDEX_URL="${PIP_EXTRA_INDEX_URL:-https://download.pytorch.org/whl/cu128}"

if ! ping -c1 github.com >/dev/null 2>&1; then
  echo "[bootstrap] WARNING: no internet connectivity"
fi

echo "[bootstrap] start (repo: $REPO_DIR)"

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

# Run modules safely
run_module() {
  local m="$1"
  if [ -x "${REPO_DIR}/modules/${m}" ]; then
    echo "[bootstrap] >>> running module: ${m}"
    bash "${REPO_DIR}/modules/${m}" >"${LOGDIR}/${m%.sh}.log" 2>&1
    echo "[bootstrap] <<< module ${m} done (log: ${LOGDIR}/${m%.sh}.log)"
  else
    echo "[bootstrap] (skipped) missing module: ${m}"
  fi
}

echo "[bootstrap] installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
if ! retry apt-get update; then
  echo "[bootstrap] switching to mirror..."
  sed -i 's|http://.*archive.ubuntu.com/ubuntu|mirror://mirrors.ubuntu.com/mirrors.txt|g; s|http://.*security.ubuntu.com/ubuntu|mirror://mirrors.ubuntu.com/mirrors.txt|g' /etc/apt/sources.list
  retry apt-get update
fi
retry apt-get install -y git aria2 unzip curl rsync procps
retry python3 -m pip install --upgrade huggingface_hub
retry python3 -m pip install --upgrade pyyaml

# Ensure ComfyUI repository exists
COMFY_DIR="${WORKDIR}/ComfyUI"
if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[bootstrap] cloning ComfyUI..."
  retry git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
else
  echo "[bootstrap] ComfyUI already present"
fi

run_module "01_jupyter.sh"
run_module "02_workspace.sh"
run_module "03_custom_nodes.sh"
run_module "04_models.sh"

echo "[bootstrap] all modules started ✅"

# Start ComfyUI in the foreground to keep the container alive
echo "[bootstrap] launching ComfyUI..."
cd "$COMFY_DIR"
exec python main.py --listen 0.0.0.0 --port "${COMFY_PORT:-8188}"

