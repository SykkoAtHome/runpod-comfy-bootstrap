#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_script="$repo_root/vast-bootstrap.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

[[ -f "$bootstrap_script" ]] || fail "vast-bootstrap.sh is missing"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

workspace="$test_root/workspace"
fake_bin="$test_root/bin"
call_log="$test_root/calls.log"
cron_file="$test_root/etc/cron.d/comfy-s3-uploader"
rclone_env_file="$test_root/etc/comfy-s3.env"
portal_log_dir="$test_root/var/log/portal"

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

cat > "$fake_bin/rclone" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rclone %s\n' "$*" >> "$CALL_LOG"
EOF

chmod +x "$fake_bin/curl" "$fake_bin/rclone"

partial_model="$workspace/ComfyUI/models/vae/minimax_h3_audio_vae_fp32.safetensors.part"
mkdir -p "$(dirname "$partial_model")"
printf 'partial-data\n' > "$partial_model"

common_env=(
    "WORKSPACE_DIR=$workspace"
    "CRON_FILE=$cron_file"
    "RCLONE_ENV_FILE=$rclone_env_file"
    "PORTAL_LOG_DIR=$portal_log_dir"
    "CURL_BIN=$fake_bin/curl"
    "RCLONE_BIN=$fake_bin/rclone"
    "CALL_LOG=$call_log"
    "RCLONE_CONFIG_SILO_ACCESS_KEY_ID=test-access-key"
)

if env -u RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY \
    "${common_env[@]}" \
    bash "$bootstrap_script" > "$test_root/missing-secret.log" 2>&1; then
    fail "bootstrap succeeded without RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"
fi
assert_contains "$test_root/missing-secret.log" "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"

env \
    "${common_env[@]}" \
    "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-secret-key" \
    bash "$bootstrap_script"

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
assert_contains "$call_log" "rclone lsd silo:comfy"
assert_contains "$cron_file" "rclone move $workspace/ComfyUI/output silo:comfy/output"
assert_contains "$cron_file" "--min-age 2m"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_ENDPOINT=https://s3.tluchowski.pl"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_ACCESS_KEY_ID=test-access-key"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-secret-key"

env \
    "${common_env[@]}" \
    "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-secret-key" \
    bash "$bootstrap_script"

[[ "$(grep -c '^curl ' "$call_log")" -eq 5 ]] || fail "existing models were downloaded again"

echo "PASS: Vast bootstrap behavior"
