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
MODELS_DIR="${WORKDIR}/models"
CFG_FILE="${WORKDIR}/runpod-comfy-bootstrap/config/models.yaml"

HF_TOKEN="${HF_TOKEN:-}"

get_env() {
  local name="$1"
  local val
  val="$(printenv "$name" 2>/dev/null || true)"
  echo "${val:-}"
}

auth_header=()
if [ -n "$HF_TOKEN" ]; then
  auth_header=(-H "Authorization: Bearer ${HF_TOKEN}")
fi

entries=()
if [ -f "$CFG_FILE" ]; then
  mapfile -t entries < <(python3 - "$CFG_FILE" <<'PY'
import sys, yaml

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}

def iter_sections(prefix, obj):
    if isinstance(obj, list):
        for item in obj or []:
            yield prefix, item
    elif isinstance(obj, dict):
        for key, val in obj.items():
            new_prefix = f"{prefix}_{key}" if prefix else key
            yield from iter_sections(new_prefix, val)

for section, item in iter_sections('', data):
    url = item.get('url')
    target = item.get('target_dir', 'diffusion_models')
    print(f"{section}\t{url}\t{target}")
PY
  )
fi
TOTAL_STEPS=${#entries[@]}
STEP=0

log_step() {
  local msg="$1"
  echo "[models] [$STEP/$TOTAL_STEPS] $msg"
}

download_file() {
  local url="$1"
  local out="$2"
  if [ -f "$out" ] && [ -s "$out" ]; then
    echo "[models] exists: $out"
    return 0
  fi
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -x 16 -s 16 -k 1M -o "$(basename "$out")" -d "$(dirname "$out")" \
      --header="${auth_header[*]}" "$url" || \
      retry curl -fL "${auth_header[@]}" --progress-bar -o "$out" "$url"
  else
    retry curl -fL "${auth_header[@]}" --progress-bar -o "$out" "$url"
  fi
  if [ ! -s "$out" ]; then
    echo "[models] download failed or empty: $url" >&2
    rm -f "$out"
    return 1
  fi
}

download_hf_resolve() {
  local repo_id="$1"
  local path="$2"
  local out="$3"
  if [ -z "$HF_TOKEN" ]; then
    echo "[models] HF_TOKEN missing; skip ${repo_id}/${path}" >&2
    return 0
  fi
  local base="https://huggingface.co"
  local mirror="https://hf-mirror.com"
  local url="${base}/${repo_id}/resolve/main/${path}"
  if ! download_file "$url" "$out"; then
    echo "[models] primary HuggingFace failed, trying mirror..."
    download_file "${mirror}/${repo_id}/resolve/main/${path}" "$out"
  fi
}

mkdir -p "${MODELS_DIR}/diffusion_models" \
         "${MODELS_DIR}/checkpoints" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/clip"

if [ -f "$CFG_FILE" ]; then
  echo "[models] reading list from ${CFG_FILE}"
  python3 - "$CFG_FILE" <<'PY' | while IFS= read -r dir; do
import sys, yaml

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}

def iter_items(obj):
    if isinstance(obj, list):
        for item in obj or []:
            yield item
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from iter_items(v)

dirs = set()
for item in iter_items(data):
    dirs.add(item.get('target_dir', 'diffusion_models'))
for d in sorted(dirs):
    print(d)
PY
    mkdir -p "${MODELS_DIR}/${dir}"
  done
  for line in "${entries[@]}"; do
    STEP=$((STEP+1))
    IFS=$'\t' read -r section url subdir <<< "$line"
    top_section="${section%%_*}"
    env_section="$(echo "${top_section}" | tr '.' '_' | tr '[:lower:]' '[:upper:]')"
    var_name="DOWNLOAD_${env_section}"
    var_value="$(get_env "$var_name")"
    var_value="${var_value:-True}"
    if [ "$var_value" != "True" ]; then
      log_step "skipping due to ${var_name}=${var_value}: $url"
      continue
    fi

    if [[ "$url" =~ ^hf:// ]]; then
      spec="${url#hf://}"
      repo_id="${spec%%/*}"
      path="${spec#*/}"
      out="${MODELS_DIR}/${subdir}/$(basename "$path")"
      mkdir -p "$(dirname "$out")"
      log_step "downloading ${url} -> ${out}"
      if ! download_hf_resolve "$repo_id" "$path" "$out"; then
        echo "[models] failed to download $url" >&2
      fi
    else
      fname="$(basename "$url")"
      out="${MODELS_DIR}/${subdir}/${fname}"
      mkdir -p "$(dirname "$out")"
      log_step "downloading ${url} -> ${out}"
      if ! download_file "$url" "$out"; then
        echo "[models] failed to download $url" >&2
      fi
    fi
  done
else
  cat <<EOF2
[models] missing ${CFG_FILE}.
Populate it with YAML sections, e.g.:

wan2.1:
  diffusion_models:
    - url: hf://owner/repo/path/to/model.safetensors
      target_dir: diffusion_models/wan2.1
  vae:
    - url: hf://owner/repo/path/to/vae.safetensors
      target_dir: vae/wan2.1

EOF2
fi

echo "[models] done."
