#!/usr/bin/env bash

JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_TOKEN="${JUPYTER_TOKEN:-changeme}"
WORKDIR="${WORKDIR:-/workspace}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

TOTAL_STEPS=2
STEP=1

log_step() {
  local msg="$1"
  echo "[Jupyter] [$STEP/$TOTAL_STEPS] $msg"
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
  # match both "jupyter lab" and "jupyter-lab" along with the configured port
  pgrep -af "jupyter( |-)?lab.*--port[= ]${JUPYTER_PORT}" >/dev/null 2>&1
}

is_port_in_use() {
  ss -ltn "sport = :${JUPYTER_PORT}" | grep -q LISTEN
}

start_jupyter() {
  if is_jupyter_running; then
    echo "[Jupyter] already running on port ${JUPYTER_PORT}."
    return
  fi
  if is_port_in_use; then
    echo "[Jupyter] port ${JUPYTER_PORT} is in use by another process; skipping"
    return
  fi

  echo "[Jupyter] starting on port ${JUPYTER_PORT}..."
  nohup python3 -m jupyterlab \
    --ip=0.0.0.0 \
    --port="${JUPYTER_PORT}" \
    --ServerApp.token="${JUPYTER_TOKEN}" \
    --ServerApp.allow_origin="*" \
    --no-browser \
    --allow-root \
    >"${LOGDIR}/jupyter.log" 2>&1 &
  # short wait and HTTP healthcheck
  for _ in $(seq 1 20); do
    sleep 1
    if curl -s "http://127.0.0.1:${JUPYTER_PORT}/api" >/dev/null 2>&1; then
      echo "[Jupyter] healthy on port ${JUPYTER_PORT}"
      break
    fi
  done
  echo "[Jupyter] logs: ${LOGDIR}/jupyter.log"
}

log_step "ensuring jupyterlab is installed"
install_jupyter_if_needed
if command -v pyenv >/dev/null 2>&1; then
  pyenv rehash
fi
STEP=$((STEP+1))
log_step "starting jupyterlab"
start_jupyter

