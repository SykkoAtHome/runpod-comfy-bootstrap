# Project memory

## Vast.ai VM deployment

- Direct S3 output uses a Vast.ai VM, not a regular Docker instance, because
  `rclone mount` requires FUSE access.
- `vast-bootstrap.sh` runs on the VM host, mounts `silo:comfy` at `/mnt/silo`,
  and manages both the mount and ComfyUI through systemd.
- ComfyUI runs from `vastai/comfy:v0.32.0-cuda-13.2-py312` in nested Docker and
  writes to `/mnt/silo/output`.
- The Vast template filters for hosts with `cuda_max_good>=13.2`; the KVM image
  is the Ubuntu 22.04 CLI image because `vastai/kvm` has no CUDA 13-tagged VM
  image.
- The template exposes VM port 18188 and sets `OPEN_BUTTON_PORT=18188`, so the
  Vast instance card can open ComfyUI without requiring an SSH tunnel.
- Vast requires an account SSH public key before creating any VM, even when the
  user only accesses ComfyUI through the public Open button.
- `vast-container-bootstrap.sh` provisions models inside the ComfyUI container.
- The mount service is a hard dependency of the ComfyUI service. Preserve this
  fail-closed behavior to avoid silently writing outputs to local storage.
- Silo credentials are supplied through Vast account environment variables;
  the access-key value is the Silo username and the secret-key value is its
  password.

## Verification

On Windows, use Git for Windows Bash because the local WSL launcher is not
functional in this workspace:

```powershell
& 'C:\Program Files\Git\usr\bin\bash.exe' -c 'export PATH=/usr/bin:/bin:$PATH; bash tests/test_vast_vm_bootstrap.sh'
& 'C:\Program Files\Git\usr\bin\bash.exe' -c 'export PATH=/usr/bin:/bin:$PATH; bash tests/test_vast_container_bootstrap.sh'
```
