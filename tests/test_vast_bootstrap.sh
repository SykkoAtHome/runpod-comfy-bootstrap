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
rclone_env_file="$test_root/etc/comfy-s3.env"
uploader_bin="$test_root/usr/local/bin/comfy-s3-uploader"
supervisor_config="$test_root/etc/supervisor/conf.d/comfy-s3-uploader.conf"
log_dir="$test_root/var/log/portal"

mkdir -p "$workspace/ComfyUI" "$fake_bin"
touch "$call_log"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >> "$CALL_LOG"
output=""
while (($#)); do
    if [[ "$1" == "--output" ]]; then
        output="$2"
        shift 2
    else
        shift
    fi
done
mkdir -p "$(dirname "$output")"
printf 'model-data\n' > "$output"
EOF

for command_name in apt-get rclone supervisorctl; do
    cat > "$fake_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >> "$CALL_LOG"
if [[ "$(basename "$0")" == "rclone" && "${1:-}" == "copyto" && "${FAIL_COPYTO:-false}" == "true" ]]; then
    exit 1
fi
EOF
done

cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$CALL_LOG"
target="${@: -1}"
mkdir -p "$target"
printf 'package\n' > "$target/requirements.txt"
EOF

cat > "$fake_bin/python" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'python %s\n' "$*" >> "$CALL_LOG"
EOF
chmod +x "$fake_bin"/*

partial_model="$workspace/ComfyUI/models/vae/minimax_h3_audio_vae_fp32.safetensors.part"
mkdir -p "$(dirname "$partial_model")"
printf 'partial-data\n' > "$partial_model"

common_env=(
    "PATH=$fake_bin:/usr/bin:/bin"
    "SKIP_ROOT_CHECK=true"
    "WORKSPACE_DIR=$workspace"
    "RCLONE_ENV_FILE=$rclone_env_file"
    "UPLOADER_BIN=$uploader_bin"
    "SUPERVISOR_CONFIG=$supervisor_config"
    "LOG_DIR=$log_dir"
    "APT_GET_BIN=$fake_bin/apt-get"
    "CURL_BIN=$fake_bin/curl"
    "GIT_BIN=$fake_bin/git"
    "PYTHON_BIN=$fake_bin/python"
    "RCLONE_BIN=$fake_bin/rclone"
    "SUPERVISORCTL_BIN=$fake_bin/supervisorctl"
    "CALL_LOG=$call_log"
    "S3_LOGIN=test-user"
)

if env -u S3_PASS \
    "NONINTERACTIVE=true" \
    "${common_env[@]}" bash "$bootstrap_script" > "$test_root/missing-secret.log" 2>&1; then
    fail "bootstrap succeeded without the Silo password"
fi
assert_contains "$test_root/missing-secret.log" "S3_PASS"

env "${common_env[@]}" \
    "S3_PASS=test-password" \
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
assert_contains "$call_log" "git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git"
assert_contains "$call_log" "python -m pip install -r"
assert_contains "$call_log" "supervisorctl reread"
assert_contains "$call_log" "supervisorctl update"
assert_contains "$call_log" "supervisorctl restart comfy-s3-uploader"
assert_contains "$call_log" "supervisorctl restart comfyui"

assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_ACCESS_KEY_ID=test-user"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-password"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_REGION=warsaw"
assert_contains "$uploader_bin" 'copyto "$file" "$remote_path"'
assert_contains "$uploader_bin" 'rm -f -- "$file"'
if grep -Fq -- 'rclone move' "$uploader_bin"; then
    fail "uploader still uses rclone move"
fi
assert_contains "$supervisor_config" "[program:comfy-s3-uploader]"
assert_contains "$supervisor_config" "command=$uploader_bin"

successful_output="$workspace/ComfyUI/output/success.png"
mkdir -p "$(dirname "$successful_output")"
printf 'image\n' > "$successful_output"
touch -d '2 minutes ago' "$successful_output"
env "CALL_LOG=$call_log" "RUN_ONCE=true" bash "$uploader_bin"
[[ ! -e "$successful_output" ]] || fail "successfully uploaded file was not removed locally"
assert_contains "$call_log" "rclone copyto $successful_output silo:comfy/output/success.png"

failed_output="$workspace/ComfyUI/output/failed.png"
printf 'image\n' > "$failed_output"
touch -d '2 minutes ago' "$failed_output"
env "CALL_LOG=$call_log" "RUN_ONCE=true" "FAIL_COPYTO=true" bash "$uploader_bin"
[[ -e "$failed_output" ]] || fail "failed upload was removed locally"

env "${common_env[@]}" \
    "S3_PASS=test-password" \
    bash "$bootstrap_script"

[[ "$(grep -c '^curl ' "$call_log")" -eq 5 ]] || fail "existing models were downloaded again"
[[ "$(grep -c '^git clone ' "$call_log")" -eq 1 ]] || fail "KJNodes was cloned more than once"
[[ "$(grep -c '^supervisorctl restart comfyui$' "$call_log")" -eq 2 ]] || fail "ComfyUI was not restarted after each bootstrap"

echo "PASS: Vast ComfyUI bootstrap installs models and configures the S3 uploader"
