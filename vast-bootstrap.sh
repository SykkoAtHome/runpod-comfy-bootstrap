#!/usr/bin/env bash

set -Eeuo pipefail

ENVIRONMENT_FILE="${ENVIRONMENT_FILE:-/etc/environment}"
if [[ -r "$ENVIRONMENT_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENVIRONMENT_FILE"
    set +a
fi

SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
LOCAL_BIN_DIR="${LOCAL_BIN_DIR:-/usr/local/bin}"
RCLONE_ENV_FILE="${RCLONE_ENV_FILE:-/etc/comfy-s3.env}"
COMFY_ENV_FILE="${COMFY_ENV_FILE:-/etc/comfy-vm.env}"
FUSE_CONFIG_FILE="${FUSE_CONFIG_FILE:-/etc/fuse.conf}"
S3_MOUNT_DIR="${S3_MOUNT_DIR:-/mnt/silo}"
RCLONE_CACHE_DIR="${RCLONE_CACHE_DIR:-/var/cache/rclone-comfy}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
LOG_DIR="${LOG_DIR:-/var/log}"

APT_GET_BIN="${APT_GET_BIN:-apt-get}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
FUSERMOUNT_BIN="${FUSERMOUNT_BIN:-fusermount3}"
MOUNTPOINT_BIN="${MOUNTPOINT_BIN:-mountpoint}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"

S3_BUCKET="${S3_BUCKET:-comfy}"
S3_PREFIX="${S3_PREFIX:-output}"
COMFY_OUTPUT_DIR="$S3_MOUNT_DIR/$S3_PREFIX"
COMFY_CONTAINER_NAME="${COMFY_CONTAINER_NAME:-comfyui}"
COMFY_IMAGE="${COMFY_IMAGE:-vastai/comfy:v0.32.0-cuda-13.2-py312}"
CONTAINER_PROVISIONING_SCRIPT="${CONTAINER_PROVISIONING_SCRIPT:-https://raw.githubusercontent.com/SykkoAtHome/runpod-comfy-bootstrap/main/vast-container-bootstrap.sh}"
MOUNT_WAIT_SECONDS="${MOUNT_WAIT_SECONDS:-60}"

require_root() {
    if [[ "${SKIP_ROOT_CHECK:-false}" != "true" && "$(id -u)" -ne 0 ]]; then
        echo "Run this bootstrap as root." >&2
        exit 1
    fi
}

require_environment() {
    : "${RCLONE_CONFIG_SILO_ACCESS_KEY_ID:?Set RCLONE_CONFIG_SILO_ACCESS_KEY_ID in Vast.ai account environment variables}"
    : "${RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY:?Set RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY in Vast.ai account environment variables}"
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 1
    }
}

install_mount_dependencies() {
    if command -v "$RCLONE_BIN" >/dev/null 2>&1 \
        && command -v "$FUSERMOUNT_BIN" >/dev/null 2>&1; then
        return
    fi

    "$APT_GET_BIN" update
    "$APT_GET_BIN" install --no-install-recommends -y fuse3 rclone
}

require_vm_commands() {
    require_command "$DOCKER_BIN"
    require_command "$FUSERMOUNT_BIN"
    require_command "$MOUNTPOINT_BIN"
    require_command "$RCLONE_BIN"
    require_command "$SYSTEMCTL_BIN"
}

enable_fuse_allow_other() {
    mkdir -p "$(dirname "$FUSE_CONFIG_FILE")"
    touch "$FUSE_CONFIG_FILE"
    if ! grep -Eq '^[[:space:]]*user_allow_other([[:space:]]|$)' "$FUSE_CONFIG_FILE"; then
        printf '\nuser_allow_other\n' >> "$FUSE_CONFIG_FILE"
    fi
}

write_rclone_environment() {
    mkdir -p "$(dirname "$RCLONE_ENV_FILE")"
    umask 077
    {
        printf 'RCLONE_CONFIG_SILO_TYPE=%q\n' "s3"
        printf 'RCLONE_CONFIG_SILO_PROVIDER=%q\n' "Minio"
        printf 'RCLONE_CONFIG_SILO_ENDPOINT=%q\n' "https://s3.tluchowski.pl"
        printf 'RCLONE_CONFIG_SILO_REGION=%q\n' "us-east-1"
        printf 'RCLONE_CONFIG_SILO_FORCE_PATH_STYLE=%q\n' "true"
        printf 'RCLONE_CONFIG_SILO_ACCESS_KEY_ID=%q\n' "$RCLONE_CONFIG_SILO_ACCESS_KEY_ID"
        printf 'RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=%q\n' "$RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"
    } > "$RCLONE_ENV_FILE"
    chmod 0600 "$RCLONE_ENV_FILE"
}

validate_s3_access() {
    echo "Checking access to silo:$S3_BUCKET..."
    set -a
    # shellcheck disable=SC1090
    . "$RCLONE_ENV_FILE"
    set +a
    "$RCLONE_BIN" lsd "silo:$S3_BUCKET" >/dev/null
}

write_rclone_service() {
    local service_file="$SYSTEMD_DIR/comfy-s3.service"
    mkdir -p "$SYSTEMD_DIR" "$S3_MOUNT_DIR" "$RCLONE_CACHE_DIR" "$LOG_DIR"

    cat > "$service_file" <<EOF
[Unit]
Description=ComfyUI S3 mount
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
EnvironmentFile=$RCLONE_ENV_FILE
ExecStart=$RCLONE_BIN mount silo:$S3_BUCKET $S3_MOUNT_DIR \\
    --allow-other \\
    --umask 002 \\
    --vfs-cache-mode writes \\
    --vfs-write-back 5s \\
    --vfs-cache-max-age 24h \\
    --vfs-cache-min-free-space 20G \\
    --vfs-fast-fingerprint \\
    --cache-dir $RCLONE_CACHE_DIR \\
    --dir-cache-time 1m \\
    --poll-interval 0 \\
    --log-file $LOG_DIR/rclone-comfy.log \\
    --log-level INFO
ExecStop=$FUSERMOUNT_BIN -uz $S3_MOUNT_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

wait_for_s3_mount() {
    local attempt
    for ((attempt = 1; attempt <= MOUNT_WAIT_SECONDS; attempt++)); do
        if "$MOUNTPOINT_BIN" -q "$S3_MOUNT_DIR"; then
            return
        fi
        sleep 1
    done

    echo "S3 mount did not become ready: $S3_MOUNT_DIR" >&2
    "$SYSTEMCTL_BIN" status comfy-s3.service --no-pager >&2 || true
    exit 1
}

write_comfy_environment() {
    mkdir -p "$(dirname "$COMFY_ENV_FILE")"
    umask 077
    {
        printf 'COMFY_CONTAINER_NAME=%q\n' "$COMFY_CONTAINER_NAME"
        printf 'COMFY_IMAGE=%q\n' "$COMFY_IMAGE"
        printf 'COMFY_OUTPUT_DIR=%q\n' "$COMFY_OUTPUT_DIR"
        printf 'CONTAINER_PROVISIONING_SCRIPT=%q\n' "$CONTAINER_PROVISIONING_SCRIPT"
        printf 'DOCKER_BIN=%q\n' "$DOCKER_BIN"
        printf 'MOUNTPOINT_BIN=%q\n' "$MOUNTPOINT_BIN"
        printf 'S3_MOUNT_DIR=%q\n' "$S3_MOUNT_DIR"
        printf 'WORKSPACE_DIR=%q\n' "$WORKSPACE_DIR"
    } > "$COMFY_ENV_FILE"
    chmod 0600 "$COMFY_ENV_FILE"
}

write_container_launcher() {
    local launcher="$LOCAL_BIN_DIR/start-comfyui-container"
    mkdir -p "$LOCAL_BIN_DIR"

    cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

set -a
. "$COMFY_ENV_FILE"
set +a

"\$MOUNTPOINT_BIN" -q "\$S3_MOUNT_DIR" || {
    echo "S3 mount is unavailable: \$S3_MOUNT_DIR" >&2
    exit 1
}

"\$DOCKER_BIN" rm -f "\$COMFY_CONTAINER_NAME" >/dev/null 2>&1 || true

exec "\$DOCKER_BIN" run \\
    --rm \\
    --name "\$COMFY_CONTAINER_NAME" \\
    --gpus all \\
    --network host \\
    --shm-size 16g \\
    -e SERVERLESS=true \\
    -e WORKSPACE=/workspace \\
    -e "COMFYUI_ARGS=--disable-auto-launch --enable-cors-header --listen 0.0.0.0 --port 18188 --output-directory \$COMFY_OUTPUT_DIR" \\
    -e "PROVISIONING_SCRIPT=\$CONTAINER_PROVISIONING_SCRIPT" \\
    -v "\$WORKSPACE_DIR:/workspace" \\
    -v "\$S3_MOUNT_DIR:\$S3_MOUNT_DIR" \\
    "\$COMFY_IMAGE"
EOF
    chmod 0755 "$launcher"
}

write_comfy_service() {
    local launcher="$LOCAL_BIN_DIR/start-comfyui-container"
    local service_file="$SYSTEMD_DIR/comfyui.service"

    cat > "$service_file" <<EOF
[Unit]
Description=ComfyUI container
Requires=docker.service comfy-s3.service
After=docker.service comfy-s3.service
BindsTo=comfy-s3.service

[Service]
Type=simple
EnvironmentFile=$COMFY_ENV_FILE
ExecStart=$launcher
ExecStop=$DOCKER_BIN stop -t 30 $COMFY_CONTAINER_NAME
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

start_services() {
    "$SYSTEMCTL_BIN" daemon-reload
    "$SYSTEMCTL_BIN" enable comfy-s3.service
    "$SYSTEMCTL_BIN" restart comfy-s3.service
    wait_for_s3_mount
    mkdir -p "$COMFY_OUTPUT_DIR" "$WORKSPACE_DIR"
    "$DOCKER_BIN" pull "$COMFY_IMAGE"
    "$SYSTEMCTL_BIN" enable comfyui.service
    "$SYSTEMCTL_BIN" restart comfyui.service
}

main() {
    require_root
    require_environment
    install_mount_dependencies
    require_vm_commands
    enable_fuse_allow_other
    write_rclone_environment
    validate_s3_access
    write_rclone_service
    write_comfy_environment
    write_container_launcher
    write_comfy_service
    start_services
    echo "Vast.ai VM bootstrap complete. ComfyUI writes to $COMFY_OUTPUT_DIR."
}

main "$@"
