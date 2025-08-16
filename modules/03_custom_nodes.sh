#!/usr/bin/env bash
set -euo pipefail

# =========[ MODUŁ 03: CUSTOM NODES ]=========
WORKDIR="${WORKDIR:-/workspace}"
COMFY_DIR="${WORKDIR}/ComfyUI"
NODES_DIR="${COMFY_DIR}/custom_nodes"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/custom_nodes.txt"

# 1) ComfyUI (jeśli nie ma)
if [ ! -d "${COMFY_DIR}/.git" ]; then
  echo "[nodes] klonuję ComfyUI…"
  git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_DIR}"
fi

# 2) ComfyUI-Manager (zawsze warto mieć)
if [ ! -d "${NODES_DIR}/ComfyUI-Manager/.git" ]; then
  echo "[nodes] instaluję ComfyUI-Manager…"
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git "${NODES_DIR}/ComfyUI-Manager"
else
  (cd "${NODES_DIR}/ComfyUI-Manager" && git pull --rebase || true)
fi

# 3) Twoje repo z listą node’ów (po jednym URL na linię w config/custom_nodes.txt)
if [ -f "$CFG_FILE" ]; then
  echo "[nodes] czytam listę z ${CFG_FILE}"
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
  echo "[nodes] Brak pliku ${CFG_FILE}. Dodaj swoje repozytoria Git (po jednym na linię)."
fi

# 4) Requirements (spróbuj zainstalować, ale nie przerywaj gdy któryś zawiedzie)
echo "[nodes] instaluję zależności Pythona…"
pip install --upgrade pip wheel setuptools
pip install -r "${COMFY_DIR}/requirements.txt" || true
for req in "${NODES_DIR}"/*/requirements.txt; do
  [ -f "$req" ] && pip install -r "$req" || true
done

# (opcjonalnie) start ComfyUI tutaj:
# nohup python "${COMFY_DIR}/main.py" --listen 0.0.0.0 --port 8188 > "${WORKDIR}/logs/comfyui.log" 2>&1 &
# =========[ /MODUŁ 03 ]=========
