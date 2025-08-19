import json
import os
import shutil
from pathlib import Path

import requests
from huggingface_hub import hf_hub_download

from .utils import env_true


CONFIG_FILE = Path(__file__).resolve().parent.parent / "config" / "models.json"
COMFY_MODELS_DIR = Path("/workspace/ComfyUI/models")
HF_CACHE_DIR = Path(os.getenv("HF_HOME", "/workspace/.cache/huggingface"))
HF_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _download_hf(url: str, dest: Path, token: str | None) -> None:
    repo_path = url[len("hf://") :]
    parts = repo_path.split("/", 2)
    repo_id = "/".join(parts[:2])
    file_path = parts[2]
    downloaded = hf_hub_download(repo_id=repo_id, filename=file_path, token=token, cache_dir=HF_CACHE_DIR)
    shutil.copy(downloaded, dest)


def _download_http(url: str, dest: Path, token: str | None) -> None:
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with requests.get(url, headers=headers, stream=True) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)


def _download_file(item: dict) -> None:
    url = item["url"]
    target_dir = COMFY_MODELS_DIR / item["target_dir"]
    target_dir.mkdir(parents=True, exist_ok=True)
    dest = target_dir / item["rename_to"]
    if dest.exists():
        return

    if url.startswith("hf://"):
        _download_hf(url, dest, os.getenv("HF_KEY"))
    else:
        token = os.getenv("CIVITAI_KEY") if "civitai" in url.lower() else None
        _download_http(url, dest, token)


def _process_group(group: dict) -> None:
    for items in group.values():
        for item in items:
            _download_file(item)


def download_models() -> None:
    if not CONFIG_FILE.exists():
        return
    with CONFIG_FILE.open() as f:
        cfg = json.load(f)

    if env_true("download_wan2_1"):
        _process_group(cfg.get("wan2.1", {}))

    if env_true("download_wan2_2"):
        _process_group(cfg.get("wan2.2", {}))

    for key, items in cfg.items():
        if key in {"wan2.1", "wan2.2"}:
            continue
        for item in items:
            _download_file(item)


if __name__ == "__main__":
    download_models()

