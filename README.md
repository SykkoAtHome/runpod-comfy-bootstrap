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

