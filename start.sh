#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace"

# store huggingface cache on persistent workspace volume
export HF_HOME="$WORKSPACE/.cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
mkdir -p "$HF_HUB_CACHE"

# ensure required python dependencies are available
pip install --no-cache-dir -r "$SCRIPT_DIR/modules/requirements.txt" >/dev/null 2>&1

# install ComfyUI
if [ ! -d "$WORKSPACE/ComfyUI" ]; then
    git clone https://github.com/comfyanonymous/ComfyUI "$WORKSPACE/ComfyUI"
fi
cd "$WORKSPACE/ComfyUI"
pip install -r requirements.txt
cd "$SCRIPT_DIR"

# install custom nodes
python -m modules.custom_nodes

# download models
if [[ "${SKIP_MODELS_DOWNLOAD,,}" =~ ^(1|true|yes|y)$ ]]; then
    echo "Skipping model downloads"
else
    python -m modules.models
fi

exit 0
