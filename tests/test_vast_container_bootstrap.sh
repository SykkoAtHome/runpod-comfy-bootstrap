#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_script="$repo_root/vast-container-bootstrap.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

[[ -f "$bootstrap_script" ]] || fail "vast-container-bootstrap.sh is missing"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

workspace="$test_root/workspace"
fake_bin="$test_root/bin"
call_log="$test_root/calls.log"

mkdir -p "$workspace/ComfyUI" "$fake_bin"
touch "$call_log"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'curl %s\n' "$*" >> "$CALL_LOG"

output=""
while (($#)); do
    case "$1" in
        --output)
            output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

[[ -n "$output" ]] || exit 2
mkdir -p "$(dirname "$output")"
printf 'model-data\n' > "$output"
EOF
chmod +x "$fake_bin/curl"

partial_model="$workspace/ComfyUI/models/vae/minimax_h3_audio_vae_fp32.safetensors.part"
mkdir -p "$(dirname "$partial_model")"
printf 'partial-data\n' > "$partial_model"

common_env=(
    "WORKSPACE_DIR=$workspace"
    "CURL_BIN=$fake_bin/curl"
    "CALL_LOG=$call_log"
)

env "${common_env[@]}" bash "$bootstrap_script"

expected_models=(
    "$workspace/ComfyUI/models/vae/minimax_h3_audio_vae_fp32.safetensors"
    "$workspace/ComfyUI/models/vae/minimax_h3_video_vae_fp16.safetensors"
    "$workspace/ComfyUI/models/diffusion_models/minimax_h3_ref2va_bf16.safetensors"
    "$workspace/ComfyUI/models/diffusion_models/minimax_h3_ref2va_int8_convrot.safetensors"
    "$workspace/ComfyUI/models/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
)

for model in "${expected_models[@]}"; do
    [[ -s "$model" ]] || fail "model was not installed: $model"
done

[[ "$(grep -c '^curl ' "$call_log")" -eq 5 ]] || fail "expected exactly five model downloads"
assert_contains "$call_log" "--continue-at -"

env "${common_env[@]}" bash "$bootstrap_script"

[[ "$(grep -c '^curl ' "$call_log")" -eq 5 ]] || fail "existing models were downloaded again"

echo "PASS: Vast container bootstrap installs models idempotently"
