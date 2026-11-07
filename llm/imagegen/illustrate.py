#!/usr/bin/env python3
"""illustrate.py — turn a story into consistent illustrations.

Two phases, so the LLM and the image model never need the GPU at the same time:

  plan   story.md + bible.json  --(local LLM, OpenAI-compatible server)-->  scenes.json
  render scenes.json            --(OpenVINO SDXL on the A770)-------------->  PNGs + contact sheet

Why not just ask the LLM for an image prompt per scene? Because it rewords each character every
time, and rewording is exactly what makes a character look different from picture to picture.
Instead the LLM only fills a small structured form (who is present, shot, action, setting, mood)
and THIS code assembles the final prompt, pasting the bible's fixed character descriptions and
art style verbatim. You can edit scenes.json between the two phases to tweak any prompt.

  python3 illustrate.py plan   --story s.md --bible b.json --llm-url http://127.0.0.1:8090/v1 --out run1
  .venv-ov/bin/python illustrate.py render --scenes run1/scenes.json --model <sdxl-ov-dir> -n 2
"""
import argparse
import json
import os
import re
import sys
import urllib.request

# SDXL's text encoders read 77 tokens each; anything beyond is silently ignored. Roughly 1.3
# tokens per English word, so ~55 words is the practical ceiling for one prompt.
MAX_WORDS = 55
SHOTS = "wide establishing shot, medium shot, close-up, over-the-shoulder shot, low-angle shot, aerial view"

FORM_PROMPT = """You are preparing ONE illustration for a story. Read the scene and describe its single
most visual moment as a JSON object. Reply with ONLY the JSON, no other text.

Known characters (use these exact names only if they are actually present): {chars}
Known locations (use one of these keys if it fits, otherwise leave ""): {locs}

JSON fields:
- "characters": every known character who is visibly present OR being spoken to in the scene
- "location": a known location key, or ""
- "shot": pick the best fit from: {shots}. Use a wide establishing shot for landscapes, buildings and
  arrivals; a medium shot for conversations; a close-up for a face or a single object.
- "action": what is visibly happening, at most 14 words, concrete and visual, no abstractions
- "setting": at most 10 words of visual details NOT already described by the known location. Do not
  repeat anything the location already says; use "" if there is nothing to add.
- "mood": a short phrase about light and atmosphere, 3 to 6 words (not a list of keywords)

SCENE:
\"\"\"{text}\"\"\""""


# ---------- pure helpers (need neither a GPU nor an LLM) ----------

def split_scenes(text, words_per_scene=250):
    """Split on markdown '## ' headings or '---' rules; otherwise group paragraphs by length."""
    parts = re.split(r"(?m)^(?:#{2,3} .*|-{3,}|\*{3,})\s*$", text)
    heads = re.findall(r"(?m)^#{2,3} (.*)$", text)
    if len(parts) > 1 and any(p.strip() for p in parts[1:]):
        scenes, hi = [], 0
        for k, p in enumerate(parts):
            if not p.strip():
                continue
            title = heads[hi] if (hi < len(heads) and k > 0) else f"Scene {len(scenes) + 1}"
            hi += 1 if k > 0 and hi < len(heads) else 0
            scenes.append({"title": title.strip(), "text": p.strip()})
        return scenes
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    scenes, cur, n = [], [], 0
    for p in paras:
        cur.append(p)
        n += len(p.split())
        if n >= words_per_scene:
            scenes.append({"title": f"Scene {len(scenes) + 1}", "text": "\n\n".join(cur)})
            cur, n = [], 0
    if cur:
        scenes.append({"title": f"Scene {len(scenes) + 1}", "text": "\n\n".join(cur)})
    return scenes


def parse_form(reply):
    """Extract the JSON object from an LLM reply; returns a dict or None."""
    m = re.search(r"\{.*\}", reply, re.S)
    if not m:
        return None
    try:
        d = json.loads(m.group(0))
    except json.JSONDecodeError:
        return None
    if not isinstance(d, dict):
        return None
    d.setdefault("characters", [])
    return d


def assemble_prompt(form, bible):
    """Build the final prompt in priority order (most important first, style last).

    Returns (prompt, warnings). Character looks and the style are pasted from the bible verbatim.
    """
    chars = bible.get("characters", {})
    locs = bible.get("locations", {})
    present = [c for c in form.get("characters", []) if c in chars]
    pieces = [form.get("shot", ""), form.get("action", "")]
    pieces += [chars[c]["look"] if isinstance(chars[c], dict) else chars[c] for c in present]
    loc = locs.get(form.get("location", ""), "")
    shot_override = ""
    if isinstance(loc, dict):  # a location may pin its own shot: {"look": "...", "shot": "wide establishing shot"}
        shot_override, loc = loc.get("shot", ""), loc.get("look", "")
    if shot_override:
        pieces[0] = shot_override
    # drop setting phrases the location text already contains (they only waste prompt words)
    setting = ", ".join(x.strip() for x in form.get("setting", "").split(",")
                        if x.strip() and x.strip().lower() not in loc.lower())
    pieces += [loc, setting, form.get("mood", ""), bible.get("style", "")]
    prompt = ", ".join(p.strip().rstrip(",") for p in pieces if p and p.strip())
    warns = []
    unknown = [c for c in form.get("characters", []) if c not in chars]
    if unknown:
        warns.append(f"characters not in bible (ignored): {unknown}")
    n = len(prompt.split())
    if n > MAX_WORDS:
        warns.append(f"prompt is {n} words; SDXL reads ~{MAX_WORDS}. The style at the end may be cut off. "
                     "Shorten the character looks or the style in the bible.")
    return prompt, warns


def scene_seed(base_seed, idx):
    return base_seed + idx * 1000


def contact_sheet(items, path, thumb=320):
    """items: list of (png_path, caption). Writes a grid image."""
    from PIL import Image, ImageDraw
    if not items:
        return
    cols = min(4, len(items))
    rows = (len(items) + cols - 1) // cols
    cap_h = 34
    sheet = Image.new("RGB", (cols * thumb, rows * (thumb + cap_h)), "white")
    d = ImageDraw.Draw(sheet)
    for k, (png, cap) in enumerate(items):
        im = Image.open(png).convert("RGB")
        im.thumbnail((thumb, thumb))
        x, y = (k % cols) * thumb, (k // cols) * (thumb + cap_h)
        sheet.paste(im, (x + (thumb - im.width) // 2, y))
        d.text((x + 6, y + thumb + 6), cap[:48], fill="black")
    sheet.save(path)


# ---------- phases ----------

def llm_form(url, model, scene_text, bible, temperature=0.2):
    prompt = FORM_PROMPT.format(chars=", ".join(bible.get("characters", {})) or "(none)",
                                locs=", ".join(bible.get("locations", {})) or "(none)",
                                shots=SHOTS, text=scene_text[:6000])
    body = json.dumps({"model": model, "temperature": temperature, "max_tokens": 600,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(url.rstrip("/") + "/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:  # nosec B310 - local server
        return json.loads(r.read())["choices"][0]["message"]["content"] or ""


def cmd_plan(a):
    bible = json.load(open(a.bible))
    scenes = split_scenes(open(a.story).read(), a.words_per_scene)
    os.makedirs(a.out, exist_ok=True)
    plan = {"story": os.path.abspath(a.story), "bible": bible, "scenes": []}
    for i, sc in enumerate(scenes):
        form = None
        for attempt in range(2):
            form = parse_form(llm_form(a.llm_url, a.llm_model, sc["text"], bible, 0.2 + 0.4 * attempt))
            if form:
                break
        if not form:
            print(f"scene {i + 1}: LLM gave no usable form; fill 'prompt' in by hand", file=sys.stderr)
            form = {"characters": [], "shot": "medium shot", "action": "", "setting": "", "mood": ""}
        prompt, warns = assemble_prompt(form, bible)
        plan["scenes"].append({"idx": i, "title": sc["title"], "excerpt": sc["text"][:240],
                               "form": form, "prompt": prompt, "negative": bible.get("negative", ""),
                               "seed": scene_seed(a.seed, i), "warnings": warns})
        print(f"[{i + 1}/{len(scenes)}] {sc['title']}: {prompt}", flush=True)
        for w in warns:
            print("    WARNING:", w, flush=True)
    path = os.path.join(a.out, "scenes.json")
    json.dump(plan, open(path, "w"), indent=2)
    print("wrote", path, "- edit any 'prompt' you like, then run the render phase.")


def cmd_reassemble(a):
    """Rebuild every prompt from the stored LLM forms and the current bible (no LLM needed)."""
    bible = json.load(open(a.bible))
    plan = json.load(open(a.scenes))
    plan["bible"] = bible
    for sc in plan["scenes"]:
        sc["prompt"], sc["warnings"] = assemble_prompt(sc["form"], bible)
        sc["negative"] = bible.get("negative", "")
        print(f"{sc['idx'] + 1}. {sc['prompt']}")
        for w in sc["warnings"]:
            print("    WARNING:", w)
    json.dump(plan, open(a.scenes, "w"), indent=2)
    print("updated", a.scenes, "(hand edits to 'prompt' were replaced)")


def cmd_render(a):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import gen
    plan = json.load(open(a.scenes))
    out = os.path.join(os.path.dirname(os.path.abspath(a.scenes)), "images")
    sheet_items = []
    for sc in plan["scenes"]:
        if a.only and sc["idx"] + 1 not in a.only:
            continue
        res = gen.generate(a.model, sc["prompt"], sc.get("negative", ""), a.width, a.height, a.steps,
                           a.guidance, sc["seed"], a.n, out, f"scene{sc['idx'] + 1:02d}",
                           extra={"scene": sc["title"], "scenes_json": os.path.abspath(a.scenes)})
        sheet_items += [(r["png"], f"{sc['idx'] + 1}. {sc['title']} (seed {r['seed']})") for r in res]
    sheet = os.path.join(os.path.dirname(out), "contact_sheet.png")
    contact_sheet(sheet_items, sheet)
    print("contact sheet:", sheet)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--story", required=True)
    p.add_argument("--bible", required=True)
    p.add_argument("--llm-url", default="http://127.0.0.1:8090/v1")
    p.add_argument("--llm-model", default="local")
    p.add_argument("--out", required=True)
    p.add_argument("--seed", type=int, default=1000)
    p.add_argument("--words-per-scene", type=int, default=250)
    ra = sub.add_parser("reassemble", help="rebuild prompts from stored forms after editing the bible")
    ra.add_argument("--scenes", required=True)
    ra.add_argument("--bible", required=True)
    r = sub.add_parser("render")
    r.add_argument("--scenes", required=True)
    r.add_argument("--model", required=True)
    r.add_argument("-n", type=int, default=2, help="variants per scene")
    r.add_argument("--width", type=int, default=1024)
    r.add_argument("--height", type=int, default=1024)
    r.add_argument("--steps", type=int, default=25)
    r.add_argument("--guidance", type=float, default=7.0)
    r.add_argument("--only", type=int, nargs="*", help="1-based scene numbers to render")
    a = ap.parse_args()
    {"plan": cmd_plan, "render": cmd_render, "reassemble": cmd_reassemble}[a.cmd](a)


if __name__ == "__main__":
    main()
