#!/usr/bin/env bash
set -euo pipefail

# ====== USTAWIENIA PODSTAWOWE ======
WORKDIR="${WORKDIR:-/workspace}"
REPO_DIR="${REPO_DIR:-${WORKDIR}/runpod-comfy-bootstrap}"
LOGDIR="${LOGDIR:-${WORKDIR}/logs}"
mkdir -p "$LOGDIR"

echo "[bootstrap] START (repo: $REPO_DIR)"

# Funkcja do bezpiecznego wykonywania modułów
run_module () {
  local m="$1"
  if [ -x "${REPO_DIR}/modules/${m}" ]; then
    echo "[bootstrap] >>> uruchamiam moduł: ${m}"
    "${REPO_DIR}/modules/${m}"
    echo "[bootstrap] <<< moduł ${m} OK"
  else
    echo "[bootstrap] (pominięto) brak modułu: ${m}"
  fi
}

# ====== KOLEJNOŚĆ MODUŁÓW ======
run_module "01_jupyter.sh"
run_module "02_workspace.sh"
run_module "03_custom_nodes.sh"
run_module "04_models.sh"

echo "[bootstrap] WSZYSTKIE MODUŁY WYSTARTOWAŁY ✅"
