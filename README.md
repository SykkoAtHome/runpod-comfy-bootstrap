# RunPod ComfyUI Bootstrap

Bootstraps a RunPod workspace with ComfyUI, custom nodes, and models.

## Usage

```
bash -lc 'cd /workspace && rm -rf runpod-comfy-bootstrap && git clone https://github.com/SykkoAtHome/runpod-comfy-bootstrap.git && bash runpod-comfy-bootstrap/start.sh'
```

The script installs prerequisites and runs four modules:

1. **Jupyter** – ensures JupyterLab is available and starts it on port 8888.
2. **Workspace** – prepares persistent directories and links them with ComfyUI.
3. **Custom nodes** – clones ComfyUI and listed custom node repositories.
4. **Models** – downloads models defined in `config/models.txt`.

Edit `config/custom_nodes.txt` and `config/models.txt` to customize what gets installed.

