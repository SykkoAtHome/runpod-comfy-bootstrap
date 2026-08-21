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
# optionally limit WAN 2.2 downloads to specific files
export WAN22_MODELS="file1.safetensors,file2.safetensors"
```

If `WAN22_MODELS` is unset, all WAN 2.2 files are downloaded when
`download_wan2_2=true`.

To skip downloading any models regardless of the above flags, set:

```bash
export SKIP_MODELS_DOWNLOAD=true
```

Run `start.sh` to execute the bootstrap process.

## Vast.ai ComfyUI template

The Vast.ai bootstrap uses the preinstalled ComfyUI from the official
`vastai/comfy` image. It downloads the required MiniMax H3 models and moves
completed ComfyUI outputs to an S3-compatible Silo bucket.

Use these template settings:

```text
PROVISIONING_SCRIPT=https://raw.githubusercontent.com/SykkoAtHome/runpod-comfy-bootstrap/main/vast-bootstrap.sh
```

Keep the On-start Script set to the image default:

```bash
entrypoint.sh
```

Do not create `/workspace/ComfyUI` in the On-start Script. The Vast.ai image
copies its bundled ComfyUI installation to that location during first boot.

Store only the following secrets in the Vast.ai account-level environment
variables:

```text
RCLONE_CONFIG_SILO_ACCESS_KEY_ID
RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY
```

The bootstrap uses `https://s3.tluchowski.pl`, bucket `comfy`, and prefix
`output`. Every minute, files older than two minutes are moved from
`/workspace/ComfyUI/output` to `silo:comfy/output`. A local file is removed
only after rclone successfully transfers it.

The four MiniMax H3 model files require approximately 100 GB. A 200 GB
instance disk is recommended.


