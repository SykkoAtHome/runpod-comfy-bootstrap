#!/usr/bin/env bash
set -euo pipefail

# =========[ MODUŁ 01: JUPYTER ]=========
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_TOKEN="${JUPYTER_TOKEN:-changeme}"
WORKDIR="${WORKDIR:-/workspace}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

ensure_python_tools() {
  python3 - <<'PY'
import sys, subprocess
def pipi(pkgs): subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", *pkgs])
pipi(["pip","setuptools","wheel"])
PY
}

install_jupyter_if_needed() {
  python3 - <<'PY'
import importlib, sys, subprocess
try:
    importlib.import_module("jupyterlab")
    print("[Jupyter] jupyterlab już zainstalowany.")
except ImportError:
    print("[Jupyter] instaluję jupyterlab…")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "jupyterlab"])
PY
}

is_jupyter_running() {
  pgrep -af "jupyter-lab.*--port=${JUPYTER_PORT}" >/dev/null 2>&1
}

start_jupyter() {
  if is_jupyter_running; then
    echo "[Jupyter] już działa na porcie ${JUPYTER_PORT}."
    return
  fi

  echo "[Jupyter] startuję na porcie ${JUPYTER_PORT}…"
  nohup jupyter lab \
    --ip=0.0.0.0 \
    --port="${JUPYTER_PORT}" \
    --ServerApp.token="${JUPYTER_TOKEN}" \
    --no-browser \
    --allow-root \
    >"${LOGDIR}/jupyter.log" 2>&1 &
  sleep 1
  echo "[Jupyter] logi: ${LOGDIR}/jupyter.log"
}

# main
ensure_python_tools
install_jupyter_if_needed
start_jupyter
# =========[ /MODUŁ 01 ]=========
