#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
REPO_DIR="${REPO_DIR:-${WORKDIR}/runpod-comfy-bootstrap}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

echo "[bootstrap] start (repo: $REPO_DIR)"

# Run modules safely
run_module() {
  local m="$1"
  if [ -x "${REPO_DIR}/modules/${m}" ]; then
    echo "[bootstrap] >>> running module: ${m}"
    "${REPO_DIR}/modules/${m}"
    echo "[bootstrap] <<< module ${m} done"
  else
    echo "[bootstrap] (skipped) missing module: ${m}"
  fi
}

echo "[bootstrap] installing prerequisites..."
pip install --upgrade huggingface_hub
apt-get update && apt-get install -y git aria2 unzip

run_module "01_jupyter.sh"
run_module "02_workspace.sh"
run_module "03_custom_nodes.sh"
run_module "04_models.sh"

echo "[bootstrap] all modules started ✅"

