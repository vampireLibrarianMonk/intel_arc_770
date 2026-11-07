#!/usr/bin/env python3
"""fetch_hf_repo.py — resumable, hash-verified download of a whole Hugging Face repo.

  python3 fetch_hf_repo.py <repo> <dest_dir> [--skip PATTERN ...] [--max-gb N]

Plain HTTPS through curl (-C - resume). The `hf` xet client stalled on this machine's slow
uplink, so it is not used. LFS files are verified against the sha256 in HF's metadata; a
mismatch leaves the .part in place and exits nonzero. Optional HF_TOKEN is read from the
environment and passed through a curl config on stdin, so it never appears in argv or logs.
Refuses to start if the download would leave < 1.5 GB free.
"""
import argparse
import fnmatch
import hashlib
import json
import os
import shutil
import subprocess  # nosec B404 - fixed argv, no shell
import sys
import time
import urllib.request


def api(repo, token):
    req = urllib.request.Request(f"https://huggingface.co/api/models/{repo}/tree/main?recursive=true")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as r:  # nosec B310 - https
        return [f for f in json.load(r) if f["type"] == "file"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def curl(url, part, token):
    # --speed-limit/--speed-time: a connection that stays under 150 KB/s for 30 s is dropped and
    # reopened (resuming with -C -). One such stalled connection once ran at 70 KB/s for hours while a
    # fresh connection on the same link got 580 KB/s.
    cmd = ["curl", "-L", "--fail", "-sS", "--retry", "5", "--retry-delay", "5",
           "--speed-limit", "150000", "--speed-time", "30", "-C", "-", "-o", part]
    cfg = f'header = "Authorization: Bearer {token}"\n' if token else ""
    cmd = cmd[:1] + (["-K", "-"] if token else []) + cmd[1:] + [url]
    return subprocess.run(cmd, input=cfg.encode() if token else None).returncode  # nosec B603


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("dest")
    ap.add_argument("--skip", nargs="*", default=[".ipynb_checkpoints*", "*/.ipynb_checkpoints/*", ".gitattributes", "README.md"])
    ap.add_argument("--max-gb", type=float, default=0)
    a = ap.parse_args()
    token = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN") or ""
    files = [f for f in api(a.repo, token) if not any(fnmatch.fnmatch(f["path"], p) for p in a.skip)]
    need = sum(f["size"] for f in files)
    os.makedirs(a.dest, exist_ok=True)
    have = sum(os.path.getsize(os.path.join(a.dest, f["path"])) for f in files
               if os.path.exists(os.path.join(a.dest, f["path"])))
    free = shutil.disk_usage(a.dest).free
    print(f"{a.repo}: {len(files)} files, {need / 1e9:.2f} GB (have {have / 1e9:.2f}); free {free / 1e9:.1f} GB", flush=True)
    if a.max_gb and need / 1e9 > a.max_gb:
        sys.exit(f"refusing: {need / 1e9:.2f} GB > --max-gb {a.max_gb}")
    if need - have > free - 1.5e9:
        sys.exit("refusing: would leave < 1.5 GB free")
    bad = 0
    for f in sorted(files, key=lambda x: x["size"]):
        path = os.path.join(a.dest, f["path"])
        os.makedirs(os.path.dirname(path), exist_ok=True)
        want = (f.get("lfs") or {}).get("oid")
        if os.path.exists(path) and os.path.getsize(path) == f["size"] and (not want or sha256(path) == want):
            continue
        part = path + ".part"
        url = f"https://huggingface.co/{a.repo}/resolve/main/{f['path']}"
        for attempt in range(1, 41):
            cur = os.path.getsize(part) if os.path.exists(part) else 0
            if cur >= f["size"]:
                break
            print(f"  {f['path']}: pass {attempt}, {cur >> 20}/{f['size'] >> 20} MiB", flush=True)
            curl(url, part, token)
            time.sleep(2)
        if not os.path.exists(part) or os.path.getsize(part) != f["size"]:
            print(f"  FAILED size {f['path']}", flush=True)
            bad += 1
            continue
        if want and sha256(part) != want:
            print(f"  FAILED sha256 {f['path']}", flush=True)
            bad += 1
            continue
        os.replace(part, path)
    print("DONE" if not bad else f"INCOMPLETE ({bad} bad)", flush=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
