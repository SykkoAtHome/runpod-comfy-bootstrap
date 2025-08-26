from pathlib import Path
import subprocess

from . import custom_nodes, models
from .utils import env_true


def ensure_comfyui() -> None:
    target = Path("/workspace/ComfyUI")
    if target.exists():
        return
    subprocess.run(
        ["git", "clone", "https://github.com/comfyanonymous/ComfyUI", str(target)],
        check=True,
    )
    subprocess.run(
        ["pip", "install", "-r", str(target / "requirements.txt")],
        check=True,
    )


def main() -> None:
    print("Installing ComfyUI...", flush=True)
    ensure_comfyui()
    print("Installing custom nodes...", flush=True)
    custom_nodes.install_custom_nodes()
    if env_true("SKIP_MODELS_DOWNLOAD"):
        print("Skipping model downloads", flush=True)
    else:
        print("Downloading models...", flush=True)
        had_download_errors = False
        try:
            models.download_models()
        except RuntimeError as e:
            if "Disk quota exceeded" in str(e):
                had_download_errors = True
                print(f"Skipping remaining setup: {e}", flush=True)
            else:
                raise
        if had_download_errors:
            print("Insufficient disk space for models. Exiting.", flush=True)
            return
    print("Starting ComfyUI...", flush=True)
    subprocess.run(["python", "/workspace/ComfyUI/main.py"], check=True)


if __name__ == "__main__":
    main()

