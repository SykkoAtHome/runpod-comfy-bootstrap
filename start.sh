#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace"

# store huggingface cache on persistent workspace volume
export HF_HOME="$WORKSPACE/.cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
mkdir -p "$HF_HUB_CACHE"

# ensure required python dependencies are available
pip install --no-cache-dir -r "$SCRIPT_DIR/modules/requirements.txt" >/dev/null 2>&1

# execute python bootstrap to install ComfyUI, custom nodes and models
cd "$SCRIPT_DIR" && python -m modules.bootstrap

