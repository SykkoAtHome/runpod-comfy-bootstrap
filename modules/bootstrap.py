from pathlib import Path
import subprocess

from . import custom_nodes, models


def ensure_comfyui() -> None:
    target = Path("/workspace/ComfyUI")
    if target.exists():
        return
    subprocess.run(
        ["git", "clone", "https://github.com/comfyanonymous/ComfyUI", str(target)],
        check=True,
    )


def main() -> None:
    print("Installing ComfyUI...", flush=True)
    ensure_comfyui()
    print("Installing custom nodes...", flush=True)
    custom_nodes.install_custom_nodes()
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

