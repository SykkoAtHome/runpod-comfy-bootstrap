# RunPod ComfyUI Bootstrap

Bootstraps a RunPod workspace with ComfyUI, custom nodes, and models.

## Usage

The repository is expected to live inside the RunPod workspace. On pod start
simply execute:

```bash
bash /workspace/runpod-comfy-bootstrap/start.sh
```

The script installs missing prerequisites on the first run and writes a marker
file `/workspace/.bootstrap_done`. Later runs detect the marker and skip the
installation step. To update the bootstrap itself, run `git pull` inside the
repository instead of re-cloning it each start.

Four modules are executed in order, each idempotent:

1. **Jupyter** – ensures JupyterLab is available and starts it on port 8888
   (can be skipped by listing `01_jupyter.sh` in `SKIP_MODULES`).
2. **Workspace** – prepares persistent directories and creates safe symlinks to
   the ComfyUI workspace.
3. **Custom nodes** – clones repositories listed in `config/custom_nodes.txt`.
   Failures to clone a node are logged but do not abort the bootstrap.
4. **Models** – downloads models defined in `config/models.yaml`. Sections
   `wan2.1` and `wan2.2` can be toggled with environment variables
   `DOWNLOAD_WAN2_1` and `DOWNLOAD_WAN2_2` set to `True`/`False`.

Common environment flags:

| Variable | Description |
| --- | --- |
| `SKIP_INSTALL=1` | Skip prerequisite installation even if `.bootstrap_done` is missing. |
| `SKIP_MODULES="01_jupyter.sh 03_custom_nodes.sh"` | Space separated list of module scripts to skip. Use `all` to skip every module. |
| `DOWNLOAD_WAN2_1=False` | Do not download models in the `wan2.1` section (similar for `DOWNLOAD_WAN2_2`). |

Module logs are written to `/workspace/logs`.

Edit `config/custom_nodes.txt` and `config/models.yaml` to control what gets installed.

### Model configuration

Models are listed in `config/models.yaml`. Top‑level keys may group related
models and contain further subsections such as `diffusion_models`, `vae`, or
`loras`. Each list entry specifies a `url` and a `target_dir` describing where
the file should be stored. The `target_dir` may include nested directories,
which will be created automatically. Example:

```yaml
wan2.1:
  diffusion_models:
    - url: hf://owner/repo/path/to/model.safetensors
      target_dir: diffusion_models/wan2.1
  vae:
    - url: hf://owner/repo/path/to/vae.safetensors
      target_dir: vae/wan2.1
```

Parsing the YAML requires [PyYAML](https://pyyaml.org); the bootstrap script
installs it automatically.
