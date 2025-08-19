from pathlib import Path
import subprocess
import sys


CONFIG_FILE = Path(__file__).resolve().parent.parent / "config" / "custom_nodes.txt"
COMFY_DIR = Path("/workspace/ComfyUI")
CUSTOM_NODES_DIR = COMFY_DIR / "custom_nodes"


def install_custom_nodes() -> None:
    CUSTOM_NODES_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_FILE.exists():
        return
    with CONFIG_FILE.open() as f:
        for line in f:
            url = line.strip()
            if not url or url.startswith("#"):
                continue
            repo_name = url.rstrip("/").split("/")[-1]
            target = CUSTOM_NODES_DIR / repo_name
            if target.exists():
                continue
            print(f"Cloning {repo_name}...", flush=True)
            subprocess.run(["git", "clone", url, str(target)], check=True)
            requirements_files = [
                target / "requirements.txt",
                target / "requirements-dev.txt",
                target / "py" / "requirements.txt",
                target / "py" / "requirements-dev.txt",
            ]
            for req_file in requirements_files:
                if req_file.exists():
                    print(f"Installing dependencies for {repo_name}...", flush=True)
                    subprocess.run(
                        [sys.executable, "-m", "pip", "install", "-r", str(req_file)],
                        check=True,
                    )
                    print(f"Installed dependencies for {repo_name}.", flush=True)
                    break


if __name__ == "__main__":
    install_custom_nodes()

