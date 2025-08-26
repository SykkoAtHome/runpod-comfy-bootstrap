import json
import os
import shutil
from pathlib import Path

import requests
from huggingface_hub import hf_hub_download, hf_hub_url
from tqdm import tqdm

from .utils import env_true


CONFIG_FILE = Path(__file__).resolve().parent.parent / "config" / "models.json"
COMFY_MODELS_DIR = Path("/workspace/ComfyUI/models")
HF_CACHE_DIR = Path(os.getenv("HF_HOME", "/workspace/.cache/huggingface"))
HF_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def _has_space(required: int) -> bool:
    free = shutil.disk_usage("/workspace").free
    return required == 0 or free >= required * 2


def _download_hf(url: str, dest: Path, token: str | None) -> None:
    repo_path = url[len("hf://") :]
    parts = repo_path.split("/", 2)
    repo_id = "/".join(parts[:2])
    file_path = parts[2]

    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        head = requests.head(hf_hub_url(repo_id=repo_id, filename=file_path), headers=headers, allow_redirects=True)
        head.raise_for_status()
        total = int(head.headers.get("Content-Length", 0))
        if total and not _has_space(total):
            print(f"Skipping download of {file_path} due to insufficient disk space", flush=True)
            return
    except Exception:
        total = 0

    print(f"Downloading {file_path}...", flush=True)
    downloaded = hf_hub_download(repo_id=repo_id, filename=file_path, token=token, cache_dir=HF_CACHE_DIR)
    shutil.copy(downloaded, dest)


def _download_http(url: str, dest: Path, token: str | None) -> None:
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with requests.get(url, headers=headers, stream=True) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length", 0))
        if total and not _has_space(total):
            print(f"Skipping download of {dest.name} due to insufficient disk space", flush=True)
            return
        with open(dest, "wb") as f, tqdm(total=total, unit="B", unit_scale=True, desc=dest.name) as pbar:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    pbar.update(len(chunk))


def _download_file(item: dict) -> bool:
    url = item["url"]
    target_dir = COMFY_MODELS_DIR / item["target_dir"]
    dest = target_dir / item["rename_to"]
    if dest.exists():
        return True
    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        if url.startswith("hf://"):
            _download_hf(url, dest, os.getenv("HF_KEY"))
        else:
            token = os.getenv("CIVITAI_KEY") if "civitai" in url.lower() else None
            _download_http(url, dest, token)
        return True
    except (OSError, RuntimeError) as e:
        print(f"Skipping download of {url}: {e}", flush=True)
        return False


def _process_group(group: dict) -> bool:
    ok = True
    for items in group.values():
        for item in items:
            if not _download_file(item):
                ok = False
    return ok


def download_models() -> None:
    if env_true("SKIP_MODELS_DOWNLOAD"):
        print("Skipping model downloads", flush=True)
        return
    if not CONFIG_FILE.exists():
        return
    with CONFIG_FILE.open() as f:
        cfg = json.load(f)

    had_errors = False

    wan21_enabled = env_true("download_wan2_1")
    wan22_enabled = env_true("download_wan2_2")
    if not (wan21_enabled or wan22_enabled):
        print("WAN model downloads disabled", flush=True)

    if wan21_enabled:
        print("Downloading wan2.1...", flush=True)
        if not _process_group(cfg.get("wan2.1", {})):
            had_errors = True

    if wan22_enabled:
        print("Downloading wan2.2...", flush=True)
        wan22 = cfg.get("wan2.2", {})
        selected = os.getenv("WAN22_MODELS")
        if selected:
            names = {n.strip() for n in selected.split(",") if n.strip()}
            filtered: dict[str, list[dict]] = {}
            for group_name, items in wan22.items():
                subset = [item for item in items if item["rename_to"] in names]
                if subset:
                    filtered[group_name] = subset
            if not _process_group(filtered):
                had_errors = True
        else:
            if not _process_group(wan22):
                had_errors = True

    for key, items in cfg.items():
        if key in {"wan2.1", "wan2.2"}:
            continue
        print(f"Downloading {key}...", flush=True)
        for item in items:
            if not _download_file(item):
                had_errors = True

    if had_errors:
        raise RuntimeError("Disk quota exceeded")


if __name__ == "__main__":
    download_models()

