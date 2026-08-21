#!/usr/bin/env bash

set -Eeuo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
CURL_BIN="${CURL_BIN:-curl}"

COMFY_DIR="$WORKSPACE_DIR/ComfyUI"
MODELS_DIR="$COMFY_DIR/models"

MODEL_SPECS=(
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae/minimax_h3_audio_vae_fp32.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae/minimax_h3_video_vae_fp16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_bf16.safetensors|diffusion_models/minimax_h3_ref2va_bf16.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_int8_convrot.safetensors|diffusion_models/minimax_h3_ref2va_int8_convrot.safetensors"
    "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors|text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors"
)

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Required command not found: $command_name" >&2
        exit 1
    }
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

main() {
    require_command "$CURL_BIN"
    [[ -d "$COMFY_DIR" ]] || {
        echo "ComfyUI directory not found: $COMFY_DIR" >&2
        exit 1
    }

    download_models
    echo "Vast.ai ComfyUI model provisioning complete."
}

main "$@"
