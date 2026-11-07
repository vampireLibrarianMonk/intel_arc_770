#!/usr/bin/env python3
"""gen.py — text-to-image on the Arc A770 with OpenVINO GenAI. Saves PNG + a JSON sidecar.

  .venv-ov/bin/python llm/imagegen/gen.py --model artifacts/imagegen/models/sdxl-base-int8-ov \
      --prompt "a lighthouse keeper reading a letter, oil painting" --seed 7 --n 2

Every image gets <name>.png and <name>.json (prompt, negative, seed, size, steps, guidance, model,
timings, library versions), so any picture can be reproduced exactly or tweaked from its sidecar.
"""
import argparse
import hashlib
import json
import os
import time

import numpy as np
import openvino as ov
import openvino_genai as og
from PIL import Image

_PIPES = {}


def load_pipe(model_dir, device="GPU"):
    key = (os.path.abspath(model_dir), device)
    if key not in _PIPES:
        t = time.time()
        _PIPES[key] = (og.Text2ImagePipeline(model_dir, device), round(time.time() - t, 1))
    return _PIPES[key]


def generate(model_dir, prompt, negative="", width=1024, height=1024, steps=25, guidance=7.0,
             seed=0, n=1, out_dir="artifacts/imagegen/out", name=None, device="GPU", extra=None):
    """Generate n images; returns a list of dicts with the saved paths and parameters."""
    pipe, load_s = load_pipe(model_dir, device)
    os.makedirs(out_dir, exist_ok=True)
    name = name or hashlib.sha1(f"{prompt}|{seed}".encode()).hexdigest()[:10]
    results = []
    for i in range(n):
        s = seed + i
        t = time.time()
        tensor = pipe.generate(prompt, negative_prompt=negative, width=width, height=height,
                               num_inference_steps=steps, guidance_scale=guidance, rng_seed=s,
                               num_images_per_prompt=1)
        secs = round(time.time() - t, 2)
        arr = np.asarray(tensor.data)[0]
        stem = f"{name}_s{s}"
        png = os.path.join(out_dir, stem + ".png")
        Image.fromarray(arr).save(png)
        meta = {"prompt": prompt, "negative": negative, "seed": s, "width": width, "height": height,
                "steps": steps, "guidance": guidance, "model": os.path.basename(os.path.abspath(model_dir)),
                "device": device, "seconds": secs, "pipeline_load_s": load_s,
                "openvino": ov.__version__, "openvino_genai": og.__version__, "extra": extra or {}}
        json.dump(meta, open(os.path.join(out_dir, stem + ".json"), "w"), indent=2)
        results.append({"png": png, **meta})
        print(f"[{i + 1}/{n}] seed={s} {width}x{height} steps={steps} {secs}s -> {png}", flush=True)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--negative", default="blurry, low quality, deformed, extra fingers, text, watermark")
    ap.add_argument("--width", type=int, default=1024)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--steps", type=int, default=25)
    ap.add_argument("--guidance", type=float, default=7.0)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("-n", type=int, default=1)
    ap.add_argument("--out", default="artifacts/imagegen/out")
    ap.add_argument("--name", default=None)
    ap.add_argument("--device", default="GPU")
    a = ap.parse_args()
    generate(a.model, a.prompt, a.negative, a.width, a.height, a.steps, a.guidance, a.seed, a.n,
             a.out, a.name, a.device)


if __name__ == "__main__":
    main()
