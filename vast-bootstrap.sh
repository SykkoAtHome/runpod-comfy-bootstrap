#!/usr/bin/env bash

set -Eeuo pipefail

ENVIRONMENT_FILE="${ENVIRONMENT_FILE:-/etc/environment}"
if [[ -r "$ENVIRONMENT_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$ENVIRONMENT_FILE"
    set +a
fi

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
RCLONE_ENV_FILE="${RCLONE_ENV_FILE:-/etc/comfy-s3.env}"
UPLOADER_BIN="${UPLOADER_BIN:-/usr/local/bin/comfy-s3-uploader}"
SUPERVISOR_CONFIG="${SUPERVISOR_CONFIG:-/etc/supervisor/conf.d/comfy-s3-uploader.conf}"
LOG_DIR="${LOG_DIR:-/var/log/portal}"

APT_GET_BIN="${APT_GET_BIN:-apt-get}"
CURL_BIN="${CURL_BIN:-curl}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
SUPERVISORCTL_BIN="${SUPERVISORCTL_BIN:-supervisorctl}"

S3_BUCKET="${S3_BUCKET:-comfy}"
S3_PREFIX="${S3_PREFIX:-output}"
UPLOAD_INTERVAL_SECONDS="${UPLOAD_INTERVAL_SECONDS:-15}"

COMFY_DIR="$WORKSPACE_DIR/ComfyUI"
MODELS_DIR="$COMFY_DIR/models"
OUTPUT_DIR="$COMFY_DIR/output"

MODEL_SPECS=(
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae/minimax_h3_audio_vae_fp32.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae/minimax_h3_video_vae_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_bf16.safetensors|diffusion_models/minimax_h3_ref2va_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_int8_convrot.safetensors|diffusion_models/minimax_h3_ref2va_int8_convrot.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors|text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
)

require_root() {
    if [[ "${SKIP_ROOT_CHECK:-false}" != "true" && "$(id -u)" -ne 0 ]]; then
        echo "Run this bootstrap as root." >&2
        exit 1
    fi
}

read_secret() {
    local prompt="$1"
    local variable_name="$2"

    if [[ "${NONINTERACTIVE:-false}" == "true" || ! -r /dev/tty ]]; then
        echo "Set $variable_name or run the bootstrap in an interactive terminal." >&2
        exit 1
    fi

    if [[ "$variable_name" == "S3_PASS" ]]; then
        read -r -s -p "$prompt" "$variable_name" < /dev/tty
        echo > /dev/tty
    else
        read -r -p "$prompt" "$variable_name" < /dev/tty
    fi
}

load_s3_credentials() {
    [[ -n "${S3_LOGIN:-}" ]] || read_secret "Silo login: " S3_LOGIN
    [[ -n "${S3_PASS:-}" ]] || read_secret "Silo password: " S3_PASS
    export S3_LOGIN S3_PASS
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 1
    }
}

install_rclone() {
    if command -v "$RCLONE_BIN" >/dev/null 2>&1; then
        return
    fi

    "$APT_GET_BIN" update
    "$APT_GET_BIN" install --no-install-recommends -y rclone
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
        printf 'RCLONE_CONFIG_SILO_ACCESS_KEY_ID=%q\n' "$S3_LOGIN"
        printf 'RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=%q\n' "$S3_PASS"
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

download_to_partial() {
    local url="$1"
    local partial="$2"
    local -a curl_args

    curl_args=(--fail --location --retry 10 --retry-delay 2 --retry-all-errors --progress-bar)
    if [[ -f "$partial" ]]; then
        curl_args+=(--continue-at -)
    fi
    "$CURL_BIN" "${curl_args[@]}" --output "$partial" "$url"
}

download_model() {
    local spec="$1"
    local url relative_path destination partial

    IFS='|' read -r url relative_path <<< "$spec"
    destination="$MODELS_DIR/$relative_path"
    partial="$destination.part"

    if [[ -s "$destination" ]]; then
        echo "Model already present: $relative_path"
        return
    fi

    mkdir -p "$(dirname "$destination")"
    echo "Downloading model: $relative_path"
    download_to_partial "$url" "$partial"
    [[ -s "$partial" ]] || {
        echo "Downloaded model is empty: $relative_path" >&2
        return 1
    }
    mv -- "$partial" "$destination"
    echo "Downloaded model: $relative_path"
}

download_models() {
    local spec pid
    local failed=0
    local -a pids=()

    for spec in "${MODEL_SPECS[@]}"; do
        download_model "$spec" &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done

    if ((failed)); then
        echo "One or more model downloads failed." >&2
        return 1
    fi
}

write_uploader() {
    mkdir -p "$(dirname "$UPLOADER_BIN")" "$OUTPUT_DIR" "$LOG_DIR"
    cat > "$UPLOADER_BIN" <<EOF
#!/usr/bin/env bash
set -u

set -a
. "$RCLONE_ENV_FILE"
set +a

OUTPUT_DIR=$(printf '%q' "$OUTPUT_DIR")
RCLONE_BIN=$(printf '%q' "$RCLONE_BIN")
S3_BUCKET=$(printf '%q' "$S3_BUCKET")
S3_PREFIX=$(printf '%q' "$S3_PREFIX")
UPLOAD_INTERVAL_SECONDS=$(printf '%q' "$UPLOAD_INTERVAL_SECONDS")

mkdir -p "\$OUTPUT_DIR"
while true; do
    "\$RCLONE_BIN" move "\$OUTPUT_DIR" "silo:\$S3_BUCKET/\$S3_PREFIX" \
        --min-age 1m \
        --delete-empty-src-dirs \
        --transfers 4 \
        --checkers 8 \
        --retries 10 \
        --low-level-retries 20 \
        --log-file $(printf '%q' "$LOG_DIR/comfy-s3-uploader.log") \
        --log-level INFO || true
    sleep "\$UPLOAD_INTERVAL_SECONDS"
done
EOF
    chmod 0755 "$UPLOADER_BIN"
}

write_supervisor_config() {
    mkdir -p "$(dirname "$SUPERVISOR_CONFIG")"
    cat > "$SUPERVISOR_CONFIG" <<EOF
[program:comfy-s3-uploader]
command=$UPLOADER_BIN
autostart=true
autorestart=true
startsecs=0
stopasgroup=true
killasgroup=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
redirect_stderr=true
EOF
}

start_services() {
    "$SUPERVISORCTL_BIN" reread
    "$SUPERVISORCTL_BIN" update
    "$SUPERVISORCTL_BIN" restart comfy-s3-uploader
    "$SUPERVISORCTL_BIN" restart comfyui
}

main() {
    require_root
    load_s3_credentials
    require_command "$CURL_BIN"
    require_command "$SUPERVISORCTL_BIN"
    [[ -d "$COMFY_DIR" ]] || {
        echo "ComfyUI directory not found: $COMFY_DIR" >&2
        exit 1
    }

    install_rclone
    require_command "$RCLONE_BIN"
    write_rclone_environment
    validate_s3_access
    download_models
    write_uploader
    write_supervisor_config
    start_services
    echo "Bootstrap complete. Finished outputs are moved to silo:$S3_BUCKET/$S3_PREFIX."
}

main "$@"
