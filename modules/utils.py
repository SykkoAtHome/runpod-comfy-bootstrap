import os


def str_to_bool(value: str) -> bool:
    """Convert common truthy strings to bool."""
    return value.strip().lower() in {"1", "true", "yes", "y"}


def env_true(name: str, default: str = "false") -> bool:
    return str_to_bool(os.getenv(name, default))

