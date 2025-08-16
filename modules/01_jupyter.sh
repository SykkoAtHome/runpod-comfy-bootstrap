#!/usr/bin/env bash
set -euo pipefail

JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_TOKEN="${JUPYTER_TOKEN:-changeme}"
WORKDIR="${WORKDIR:-/workspace}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

ensure_python_tools() {
  python3 - <<'PY'
import sys, subprocess
subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"])
PY
}

install_jupyter_if_needed() {
  python3 - <<'PY'
import importlib, sys, subprocess
try:
    importlib.import_module("jupyterlab")
    print("[Jupyter] jupyterlab already installed.")
except ImportError:
    print("[Jupyter] installing jupyterlab...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "jupyterlab"])
PY
}

is_jupyter_running() {
  pgrep -af "jupyter-lab.*--port=${JUPYTER_PORT}" >/dev/null 2>&1
}

start_jupyter() {
  if is_jupyter_running; then
    echo "[Jupyter] already running on port ${JUPYTER_PORT}."
    return
  fi

  echo "[Jupyter] starting on port ${JUPYTER_PORT}..."
  nohup jupyter lab \
    --ip=0.0.0.0 \
    --port="${JUPYTER_PORT}" \
    --ServerApp.token="${JUPYTER_TOKEN}" \
    --no-browser \
    --allow-root \
    >"${LOGDIR}/jupyter.log" 2>&1 &
  sleep 1
  echo "[Jupyter] logs: ${LOGDIR}/jupyter.log"
}

ensure_python_tools
install_jupyter_if_needed
start_jupyter

