# RunPod ComfyUI Bootstrap

Bootstraps a RunPod workspace with ComfyUI, custom nodes, and models.

## Usage

Put the following in the RunPod **Start Command** to clone this repository,
run the bootstrap script, and launch ComfyUI:

```bash
bash -lc 'cd /workspace && rm -rf runpod-comfy-bootstrap && \
git clone https://github.com/SykkoAtHome/runpod-comfy-bootstrap.git && \
bash runpod-comfy-bootstrap/start.sh && \
cd /workspace/ComfyUI && \
python main.py --listen 0.0.0.0 --port ${COMFY_PORT:-8188}'
```

The command installs prerequisites, runs four modules, and then starts ComfyUI:

1. **Jupyter** – ensures JupyterLab is available and starts it on port 8888 using `python3 -m jupyterlab`; it's monitored with a simple HTTP health check.
2. **Workspace** – prepares persistent directories and links them with ComfyUI. The `ComfyUI/models` directory is symlinked to `/workspace/models`, avoiding duplication.
3. **Custom nodes** – clones listed custom nodes repositories. Some plugins automatically install extra dependencies such as `sageattention` and `onnxruntime`.
4. **Models** – downloads models defined in `config/models.yaml`. Sections can be
   toggled with environment variables such as `download_wan2_1_diffusion_models`
   or `download_text_encoders` set to `True`/`False`.

Edit `config/custom_nodes.txt` and `config/models.yaml` to customize what gets installed.

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
