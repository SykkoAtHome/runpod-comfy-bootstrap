#!/usr/bin/env bash

set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/comfy-s3-uploader}"
RCLONE_ENV_FILE="${RCLONE_ENV_FILE:-/etc/comfy-s3.env}"
PORTAL_LOG_DIR="${PORTAL_LOG_DIR:-/var/log/portal}"
CURL_BIN="${CURL_BIN:-curl}"
RCLONE_BIN="${RCLONE_BIN:-rclone}"
RCLONE_CRON_BIN="${RCLONE_CRON_BIN:-rclone}"
S3_BUCKET="${S3_BUCKET:-comfy}"
S3_PREFIX="${S3_PREFIX:-output}"

COMFY_DIR="$WORKSPACE_DIR/ComfyUI"
OUTPUT_DIR="$COMFY_DIR/output"
MODELS_DIR="$COMFY_DIR/models"

MODEL_SPECS=(
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae/minimax_h3_audio_vae_fp32.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae/minimax_h3_video_vae_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_bf16.safetensors|diffusion_models/minimax_h3_ref2va_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors|text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
)

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 1
    }
}

require_environment() {
    : "${RCLONE_CONFIG_SILO_ACCESS_KEY_ID:?Set RCLONE_CONFIG_SILO_ACCESS_KEY_ID in Vast.ai account environment variables}"
    : "${RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY:?Set RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY in Vast.ai account environment variables}"
}

write_rclone_environment() {
    export RCLONE_CONFIG_SILO_TYPE="s3"
    export RCLONE_CONFIG_SILO_PROVIDER="Minio"
    export RCLONE_CONFIG_SILO_ENDPOINT="https://s3.tluchowski.pl"
    export RCLONE_CONFIG_SILO_REGION="us-east-1"
    export RCLONE_CONFIG_SILO_FORCE_PATH_STYLE="true"

    mkdir -p "$(dirname "$RCLONE_ENV_FILE")"
    umask 077
    {
        printf 'RCLONE_CONFIG_SILO_TYPE=%q\n' "$RCLONE_CONFIG_SILO_TYPE"
        printf 'RCLONE_CONFIG_SILO_PROVIDER=%q\n' "$RCLONE_CONFIG_SILO_PROVIDER"
        printf 'RCLONE_CONFIG_SILO_ENDPOINT=%q\n' "$RCLONE_CONFIG_SILO_ENDPOINT"
        printf 'RCLONE_CONFIG_SILO_REGION=%q\n' "$RCLONE_CONFIG_SILO_REGION"
        printf 'RCLONE_CONFIG_SILO_FORCE_PATH_STYLE=%q\n' "$RCLONE_CONFIG_SILO_FORCE_PATH_STYLE"
        printf 'RCLONE_CONFIG_SILO_ACCESS_KEY_ID=%q\n' "$RCLONE_CONFIG_SILO_ACCESS_KEY_ID"
        printf 'RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=%q\n' "$RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY"
    } > "$RCLONE_ENV_FILE"
    chmod 0600 "$RCLONE_ENV_FILE"
}

configure_s3_uploader() {
    echo "Checking access to silo:$S3_BUCKET..."
    "$RCLONE_BIN" lsd "silo:$S3_BUCKET" >/dev/null

    mkdir -p "$OUTPUT_DIR" "$PORTAL_LOG_DIR" "$(dirname "$CRON_FILE")"

    local cron_command
    cron_command="set -a; . $RCLONE_ENV_FILE; set +a; flock -n /tmp/comfy-s3-uploader.lock $RCLONE_CRON_BIN move $OUTPUT_DIR silo:$S3_BUCKET/$S3_PREFIX --min-age 2m --delete-empty-src-dirs --transfers 4 --checkers 8 --retries 10 --low-level-retries 20 --log-file $PORTAL_LOG_DIR/comfy-s3-uploader.log --log-level INFO"
    printf "* * * * * root /bin/bash -lc '%s'\n" "$cron_command" > "$CRON_FILE"
    chmod 0644 "$CRON_FILE"
    echo "S3 uploader configured for silo:$S3_BUCKET/$S3_PREFIX."
}

download_to_partial() {
    local url="$1"
    local partial="$2"
    local -a curl_args

    curl_args=(
        --fail
        --location
        --retry 10
        --retry-delay 2
        --retry-all-errors
        --progress-bar
    )
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
        return 0
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

restart_comfyui_if_available() {
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl restart comfyui || echo "ComfyUI will start after provisioning completes."
    fi
}

main() {
    require_environment
    require_command "$CURL_BIN"
    require_command "$RCLONE_BIN"
    [[ -d "$COMFY_DIR" ]] || {
        echo "ComfyUI directory not found: $COMFY_DIR" >&2
        exit 1
    }

    write_rclone_environment
    configure_s3_uploader
    download_models
    restart_comfyui_if_available
    echo "Vast.ai ComfyUI bootstrap complete."
}

main "$@"

