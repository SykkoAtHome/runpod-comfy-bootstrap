#!/usr/bin/env bash
set -e

# temporary workspace
TMP=$(mktemp -d)
WORK="$TMP/workspace"
REPO_SRC="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$WORK"

# stub ComfyUI so start.sh doesn't clone full repo
mkdir -p "$WORK/ComfyUI"
git -C "$WORK/ComfyUI" init >/dev/null
cat > "$WORK/ComfyUI/main.py" <<'PY'
import time
print("dummy ComfyUI")
time.sleep(3600)
PY

# copy bootstrap repo into workspace
cp -R "$REPO_SRC" "$WORK/runpod-comfy-bootstrap"

# minimal configs to avoid heavy downloads
echo '' > "$WORK/runpod-comfy-bootstrap/config/custom_nodes.txt"
cat > "$WORK/runpod-comfy-bootstrap/config/models.yaml" <<'YAML'
wan2.1:
  diffusion_models:
    - url: https://raw.githubusercontent.com/comfyanonymous/ComfyUI/master/LICENSE
      target_dir: diffusion_models/wan2.1
other:
  diffusion_models:
    - url: https://raw.githubusercontent.com/comfyanonymous/ComfyUI/master/LICENSE
      target_dir: diffusion_models/other
YAML

run_start() {
  local label="$1"
  local log="$TMP/${label}.log"
  (
    WORKDIR="$WORK" \
    REPO_DIR="$WORK/runpod-comfy-bootstrap" \
    SKIP_MODULES="01_jupyter.sh 03_custom_nodes.sh" \
    DOWNLOAD_WAN2_1=False \
    SKIP_COMFY=1 \
    bash "$WORK/runpod-comfy-bootstrap/start.sh" >"$log" 2>&1
  ) &
  pid=$!
  for i in {1..600}; do
    grep -q "SKIP_COMFY=1" "$log" && break
    sleep 1
  done
  kill $pid >/dev/null 2>&1 || true
  wait $pid 2>/dev/null || true
  echo "$log"
}

LOG1=$(run_start first)
LOG2=$(run_start second)

[ -f "$WORK/.bootstrap_done" ] || { echo "missing bootstrap marker"; exit 1; }
grep -q "prerequisites already installed" "$LOG2" || { echo "install reran on second start"; exit 1; }
[ -f "$WORK/models/diffusion_models/other/LICENSE" ] || { echo "model download failed"; exit 1; }
[ ! -f "$WORK/models/diffusion_models/wan2.1/LICENSE" ] || { echo "wan2.1 should be skipped"; exit 1; }

echo "bootstrap test passed"

