#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace"

# ensure required python dependencies are available
pip install --no-cache-dir -r "$SCRIPT_DIR/modules/requirements.txt" >/dev/null 2>&1

# execute python bootstrap to install ComfyUI, custom nodes and models
python "$SCRIPT_DIR/modules/bootstrap.py"

