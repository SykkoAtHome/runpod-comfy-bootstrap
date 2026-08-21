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

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        fail "$file unexpectedly contains: $unexpected"
    fi
}

[[ -f "$bootstrap_script" ]] || fail "vast-bootstrap.sh is missing"
assert_contains "$bootstrap_script" 'COMFY_IMAGE="${COMFY_IMAGE:-vastai/comfy:v0.32.0-cuda-13.2-py312}"'

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fake_bin="$test_root/bin"
call_log="$test_root/calls.log"
systemd_dir="$test_root/etc/systemd/system"
local_bin_dir="$test_root/usr/local/bin"
rclone_env_file="$test_root/etc/comfy-s3.env"
comfy_env_file="$test_root/etc/comfy-vm.env"
fuse_config_file="$test_root/etc/fuse.conf"
mount_dir="$test_root/mnt/silo"
cache_dir="$test_root/var/cache/rclone"
workspace_dir="$test_root/workspace"
log_dir="$test_root/var/log"

mkdir -p "$fake_bin"
touch "$call_log"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
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

for command_name in apt-get docker fusermount3 mountpoint rclone systemctl; do
    cat > "$fake_bin/$command_name" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "$(basename "$0")" "$*" >> "$CALL_LOG"
EOF
done
chmod +x "$fake_bin"/*
mkdir -p "$workspace_dir/ComfyUI"

common_env=(
    "PATH=$fake_bin:/usr/bin:/bin"
    "SKIP_ROOT_CHECK=true"
    "CALL_LOG=$call_log"
    "SYSTEMD_DIR=$systemd_dir"
    "LOCAL_BIN_DIR=$local_bin_dir"
    "RCLONE_ENV_FILE=$rclone_env_file"
    "CRON_FILE=$test_root/etc/cron.d/comfy-s3-uploader"
    "PORTAL_LOG_DIR=$test_root/var/log/portal"
    "COMFY_ENV_FILE=$comfy_env_file"
    "FUSE_CONFIG_FILE=$fuse_config_file"
    "S3_MOUNT_DIR=$mount_dir"
    "RCLONE_CACHE_DIR=$cache_dir"
    "WORKSPACE_DIR=$workspace_dir"
    "LOG_DIR=$log_dir"
    "APT_GET_BIN=$fake_bin/apt-get"
    "DOCKER_BIN=$fake_bin/docker"
    "FUSERMOUNT_BIN=$fake_bin/fusermount3"
    "MOUNTPOINT_BIN=$fake_bin/mountpoint"
    "RCLONE_BIN=$fake_bin/rclone"
    "CURL_BIN=$fake_bin/curl"
    "SYSTEMCTL_BIN=$fake_bin/systemctl"
    "COMFY_IMAGE=vastai/comfy:test"
    "RCLONE_CONFIG_SILO_ACCESS_KEY_ID=test-user"
)

if env -u RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY \
    "${common_env[@]}" \
    bash "$bootstrap_script" > "$test_root/missing-secret.log" 2>&1; then
    fail "bootstrap succeeded without RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"
fi
assert_contains "$test_root/missing-secret.log" "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"

env \
    "${common_env[@]}" \
    "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-password" \
    bash "$bootstrap_script"

rclone_service="$systemd_dir/comfy-s3.service"
comfy_service="$systemd_dir/comfyui.service"
container_launcher="$local_bin_dir/start-comfyui-container"

assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_TYPE=s3"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_ACCESS_KEY_ID=test-user"
assert_contains "$rclone_env_file" "RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=test-password"
assert_contains "$rclone_service" "Type=notify"
assert_contains "$rclone_service" "mount silo:comfy $mount_dir"
assert_contains "$rclone_service" "--vfs-cache-mode writes"
assert_contains "$rclone_service" "--cache-dir $cache_dir"
assert_contains "$rclone_service" "ExecStop=$fake_bin/fusermount3 -uz $mount_dir"
assert_not_contains "$rclone_service" "rclone move"

assert_contains "$comfy_service" "Requires=docker.service comfy-s3.service"
assert_contains "$comfy_service" "After=docker.service comfy-s3.service"
assert_contains "$comfy_service" "ExecStart=$container_launcher"
assert_contains "$container_launcher" '"$MOUNTPOINT_BIN" -q "$S3_MOUNT_DIR"'
assert_contains "$container_launcher" '"$DOCKER_BIN" run'
assert_contains "$container_launcher" "--gpus all"
assert_contains "$container_launcher" '--listen 0.0.0.0 --port 18188'
assert_contains "$container_launcher" '--output-directory $COMFY_OUTPUT_DIR'
assert_contains "$container_launcher" '"$S3_MOUNT_DIR:$S3_MOUNT_DIR"'
assert_contains "$comfy_env_file" "COMFY_OUTPUT_DIR=$mount_dir/output"
assert_contains "$comfy_env_file" "COMFY_IMAGE=vastai/comfy:test"
assert_contains "$comfy_env_file" "CONTAINER_PROVISIONING_SCRIPT=https://raw.githubusercontent.com/SykkoAtHome/runpod-comfy-bootstrap/main/vast-container-bootstrap.sh"
assert_not_contains "$comfy_env_file" "test-password"

assert_contains "$call_log" "rclone lsd silo:comfy"
assert_contains "$call_log" "docker pull vastai/comfy:test"
assert_contains "$call_log" "systemctl enable comfy-s3.service"
assert_contains "$call_log" "mountpoint -q $mount_dir"
assert_contains "$call_log" "systemctl enable comfyui.service"

echo "PASS: Vast VM bootstrap mounts S3 before starting ComfyUI"
