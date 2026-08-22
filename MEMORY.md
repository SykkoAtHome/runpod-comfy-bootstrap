# Project memory

## Vast.ai ComfyUI deployment

- Use the recommended standard Vast.ai ComfyUI Docker template for broad GPU
  compatibility. Do not require a VM.
- Standard Vast Docker containers cannot mount remote S3 through FUSE. The
  supported design keeps ComfyUI output local and moves completed files to S3.
- `vast-bootstrap.sh` is run manually after the ComfyUI container starts.
- Vast account secrets are named `S3_LOGIN` and `S3_PASS`; their values are the
  Silo username and password. If Vast does not inject them into the running
  shell, the bootstrap securely prompts for missing values through `/dev/tty`.
- The Silo S3 signing region is `warsaw`; `us-east-1` causes an
  `AuthorizationHeaderMalformed` response.
- The bootstrap installs ComfyUI-KJNodes, downloads MiniMax H3 models, validates
  `silo:comfy`, and installs a Supervisor-managed rclone uploader. Always
  restart ComfyUI once at the end so Python custom-node changes are loaded.
- The uploader moves files older than one minute from
  `/workspace/ComfyUI/output` to `silo:comfy/output` every 15 seconds.

## Verification

On Windows, use Git for Windows Bash because the local WSL launcher is not
functional in this workspace:

```powershell
& 'C:\Program Files\Git\usr\bin\bash.exe' -c 'export PATH=/usr/bin:/bin:$PATH; bash tests/test_vast_bootstrap.sh'
```
