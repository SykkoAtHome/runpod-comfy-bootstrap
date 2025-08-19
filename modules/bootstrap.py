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
    ensure_comfyui()
    custom_nodes.install_custom_nodes()
    models.download_models()


if __name__ == "__main__":
    main()

