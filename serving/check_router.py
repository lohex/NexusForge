#!/usr/bin/env python3
"""Check whether port 8080 serves the requested NexusForge llama.cpp router.

Exit 0: compatible; 10: nothing listening; 11: incompatible or unreachable.
"""

import configparser
import errno
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
URL = "http://127.0.0.1:8080/models"


def expected(backend):
    if backend == "bonsai":
        llama_dir = Path(os.environ.get("BONSAI_LLAMA_DIR", ROOT / "llama.cpp-bonsai"))
        preset = ROOT / "config/router-models-bonsai.ini"
    elif backend == "standard":
        llama_dir = ROOT / "llama.cpp"
        preset = ROOT / "config/router-models.ini"
    else:
        raise ValueError("NEXUSFORGE_LLAMA_BACKEND must be bonsai or standard")
    config = configparser.ConfigParser(interpolation=None)
    try:
        contents = preset.read_text()
        # llama.cpp presets have a mandatory `version = 1` header before sections.
        config.read_string("[meta]\n" + contents)
    except (OSError, configparser.Error) as exc:
        raise ValueError(f"Cannot read router preset {preset}: {exc}") from exc
    ids = set(config.sections()) - {"meta", "*"}
    return (llama_dir.expanduser().resolve() / "build/bin/llama-server", ids)


def check(backend):
    binary, required = expected(backend)
    try:
        with urllib.request.urlopen(URL, timeout=2) as response:
            data = json.load(response)
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, ConnectionRefusedError) or getattr(exc.reason, "errno", None) == errno.ECONNREFUSED:
            return 10
        return 11
    except (TimeoutError, ValueError, OSError):
        return 11
    try:
        models = data["data"]
        by_id = {model["id"]: model for model in models}
        if not required.issubset(by_id):
            return 11
        for name in required:
            args = by_id[name]["status"]["args"]
            if Path(args[0]).resolve() != binary:
                return 11
        return 0
    except (KeyError, IndexError, TypeError, ValueError):
        return 11


if __name__ == "__main__":
    try:
        sys.exit(check(sys.argv[1] if len(sys.argv) > 1 else "bonsai"))
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(11)
