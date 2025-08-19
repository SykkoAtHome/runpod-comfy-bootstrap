# runpod-comfy-bootstrap

This repository bootstraps a ComfyUI environment by installing the main
application, custom nodes, and optional model files.

## WAN 2.x models

Downloading WAN 2.x models is disabled by default to avoid large downloads.
Set the following environment variables to `true` before running the
bootstrap script if you want to fetch them:

```bash
export download_wan2_1=true  # WAN 2.1 models
export download_wan2_2=true  # WAN 2.2 models
```

Run `start.sh` to execute the bootstrap process.

