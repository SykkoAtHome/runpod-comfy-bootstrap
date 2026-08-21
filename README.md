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

S3 is mounted on the Vast.ai host before ComfyUI starts. This requires a Vast
virtual machine because a regular Vast Docker instance cannot be given the
FUSE device and capabilities required by `rclone mount`.

Vast requires at least one account-level SSH public key before it will create
any VM, even when ComfyUI is accessed directly with the **Open** button. Add the
key on the Vast **Keys** page before renting the instance.

Create the template from the recommended **Ubuntu 22.04 VM** template, then use:

```text
Image: docker.io/vastai/kvm:ubuntu_cli_22.04-2025-11-21
Launch mode: SSH
Extra Filters: vms_enabled=true cuda_max_good>=13.2
Docker Options: -p 18188:18188 -e OPEN_BUTTON_PORT=18188
Recommended disk: 200 GB
```

Keep the template private. Add these two secrets under the Vast.ai
account-level environment variables. Their values are the Silo username and
password respectively:

```text
RCLONE_CONFIG_SILO_ACCESS_KEY_ID=<SILO_USERNAME>
RCLONE_CONFIG_SILO_SECRET_ACCESS_KEY=<SILO_PASSWORD>
```

Set the template's **On-start Script** to:

```bash
#!/bin/bash
set -euo pipefail
curl --fail --location --retry 10 \
  https://raw.githubusercontent.com/SykkoAtHome/runpod-comfy-bootstrap/main/vast-bootstrap.sh \
  | bash
```

The script performs the following steps:

1. Mounts `silo:comfy` at `/mnt/silo` with rclone VFS write caching.
2. Starts `vastai/comfy:v0.32.0-cuda-13.2-py312` in Docker inside the VM.
3. Starts ComfyUI with `--output-directory /mnt/silo/output`.
4. Downloads the five MiniMax H3 model files into the local `/workspace`.

The ComfyUI service refuses to start if the S3 mount is unavailable, so files
cannot silently fall back to the VM's local `output` directory. Completed files
are uploaded after they are closed and the five-second VFS write-back period
has elapsed.

Open ComfyUI with the **Open** button on the Vast instance card. Alternatively,
open **IP Port Info** and use the public address mapped to `18188/tcp`. The
external port can differ from `18188`.

The direct port is public and ComfyUI does not provide authentication by
default. Remove the `-p 18188:18188` and `OPEN_BUTTON_PORT` options if the
instance must only be accessible through a private SSH tunnel.

Check service state and logs with:

```bash
systemctl status comfy-s3 comfyui
journalctl -u comfy-s3 -u comfyui -f
tail -f /var/log/rclone-comfy.log
```

The five MiniMax H3 model files require approximately 134 GB. A 200 GB
instance disk is recommended.
