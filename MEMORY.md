# Project memory

## Vast.ai ComfyUI deployment

- Use the recommended standard Vast.ai ComfyUI Docker template for broad GPU
  compatibility. Do not require a VM.
- Standard Vast Docker containers cannot mount remote S3 through FUSE. The
  supported design keeps ComfyUI output local and moves completed files to S3.
- `vast-bootstrap.sh` is run manually after the ComfyUI container starts.
- Vast account secrets are named `S3_LOGIN` and `S3_PASS`; their values are the
  Silo username and password.
- The bootstrap downloads MiniMax H3 models, validates `silo:comfy`, installs a
  Supervisor-managed rclone uploader, and restarts ComfyUI.
- The uploader moves files older than one minute from
  `/workspace/ComfyUI/output` to `silo:comfy/output` every 15 seconds.

## Verification

On Windows, use Git for Windows Bash because the local WSL launcher is not
functional in this workspace:

```powershell
& 'C:\Program Files\Git\usr\bin\bash.exe' -c 'export PATH=/usr/bin:/bin:$PATH; bash tests/test_vast_bootstrap.sh'
```
