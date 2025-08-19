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
    models.download_models()


if __name__ == "__main__":
    main()

