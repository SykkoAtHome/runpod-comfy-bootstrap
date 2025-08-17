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
4. **Models** – downloads models defined in `config/models.txt`.

Edit `config/custom_nodes.txt` and `config/models.txt` to customize what gets installed.
