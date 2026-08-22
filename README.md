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

Use the recommended standard **ComfyUI** Docker template. A regular Vast
container cannot mount S3 through FUSE, so completed local outputs are moved to
S3 automatically by a Supervisor-managed rclone uploader.

Add these account-level environment variables:

```text
S3_LOGIN=<SILO_USERNAME>
S3_PASS=<SILO_PASSWORD>
```

If either variable is unavailable inside the running container, the bootstrap
prompts for it interactively. The password input is hidden and is not written
to shell history.

Allocate at least 200 GB of disk space. Start the instance, open its terminal,
and run:

```bash
curl --fail --location --retry 10 \
  https://raw.githubusercontent.com/SykkoAtHome/runpod-comfy-bootstrap/main/vast-bootstrap.sh \
  | bash
```

The script performs the following steps:

1. Validates access to `silo:comfy`.
2. Installs ComfyUI-KJNodes and its Python requirements when missing.
3. Downloads the five MiniMax H3 model files with retry and resume support.
4. Installs a persistent `comfy-s3-uploader` Supervisor service.

The bootstrap restarts ComfyUI once at the end so installed or updated Python
custom nodes are loaded reliably.

ComfyUI writes to `/workspace/ComfyUI/output`. Every 15 seconds the uploader
copies each file older than one minute to `silo:comfy/output`. A local file is
removed individually only when its `rclone copyto` operation succeeds. Failed
uploads remain local and are retried. Check status and logs with:

```bash
supervisorctl status comfy-s3-uploader comfyui
tail -f /var/log/portal/comfy-s3-uploader.log
```

The five MiniMax H3 model files require approximately 134 GB. A 200 GB
instance disk is recommended.
