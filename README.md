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
python main.py --listen 0.0.0.0 --port 8188'
```

The command installs prerequisites, runs four modules, and then starts ComfyUI:

1. **Jupyter** – ensures JupyterLab is available and starts it on port 8888.
2. **Workspace** – prepares persistent directories and links them with ComfyUI.
3. **Custom nodes** – clones listed custom nodes repositories.
4. **Models** – downloads models defined in `config/models.txt`.

Edit `config/custom_nodes.txt` and `config/models.txt` to customize what gets installed.
