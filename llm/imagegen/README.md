# imagegen — illustrations for storywriting on the Arc A770

Goal: pictures for your stories where **a character looks the same from scene to scene** and the
art style stays fixed. Built on OpenVINO GenAI (GPU) with OpenVINO's pre-converted SDXL.

## Status (2026-11-07)

| part | state |
|:--|:--|
| `fetch_hf_repo.py` — resumable, sha256-verified repo download | used for the SDXL download (running) |
| `illustrate.py plan` / `run_plan.sh` — story + bible → `scenes.json` via a local LLM | **tested** with Llama-3.1-8B and gpt-oss-20b on the example story |
| `illustrate.py reassemble` — rebuild prompts after editing the bible | **tested** |
| `gen.py`, `illustrate.py render` — SDXL on the GPU, PNG + JSON sidecar, contact sheet | **written, NOT yet run**: waiting on the SDXL model download (3.5 GB at ~0.57 MB/s) |
| Character consistency across scenes | **unproven**; the design keeps character text fixed, but whether SDXL renders the same face is only known once images exist. LoRA adapters are supported by the pipeline and are the next step if it isn't consistent enough |

## How it works

1. **Bible** (`examples/lighthouse_bible.json`): the art style, a negative prompt, each character's
   fixed `look`, and each location's `look` plus an optional pinned `shot`.
2. **Plan**: a local LLM reads each scene and fills a small form (characters present, shot, action,
   setting, mood). It does *not* write the prompt. The code assembles the prompt, pasting the
   bible's character and style text verbatim, so wording never drifts between scenes.
3. **Edit** `scenes.json` if you like (any `prompt` can be changed by hand).
4. **Render**: SDXL renders N variants per scene; a contact sheet shows them all.

```bash
# 1. plan (starts and stops the LLM itself; default Llama-3.1-8B)
bash llm/imagegen/run_plan.sh my_story.md my_bible.json artifacts/imagegen/runs/my_story

# 2. (optional) edit artifacts/imagegen/runs/my_story/scenes.json, or change the bible and:
python3 llm/imagegen/illustrate.py reassemble --scenes artifacts/imagegen/runs/my_story/scenes.json --bible my_bible.json

# 3. render, 2 variants per scene
.venv-ov/bin/python llm/imagegen/illustrate.py render \
    --scenes artifacts/imagegen/runs/my_story/scenes.json \
    --model artifacts/imagegen/models/sdxl-base-int8-ov -n 2
```

Scenes split on `##` headings or `---` rules; a story with neither is grouped by ~250 words.

## Known limits

- **Prompt length:** SDXL reads about 55 words. The planner warns when a prompt goes over, because
  the art style at the end is what gets cut off. Keep character and location looks short.
- **Shots:** both LLMs tried picked "medium shot" for every scene, so pin a `shot` on locations in
  the bible when you want a wide establishing shot.
- **Characters not named in the text** are left out by the LLM (a scene saying only "he said" will
  not include anyone). Name them, or add them to `scenes.json`.
- The model download shares one ~0.57 MB/s link; measured parallel connections do not speed it up.
