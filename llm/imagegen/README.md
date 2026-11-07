# imagegen — illustrations for storywriting on the Arc A770

Goal: pictures for your stories where **a character looks the same from scene to scene** and the
art style stays fixed. Built on OpenVINO GenAI (GPU) with OpenVINO's pre-converted SDXL.

## Status (2026-11-07)

| part | state |
|:--|:--|
| `fetch_hf_repo.py` — resumable, sha256-verified repo download | used for the SDXL download (done, hashes verified) |
| `illustrate.py plan` / `run_plan.sh` — story + bible → `scenes.json` via a local LLM | **tested** with Llama-3.1-8B and gpt-oss-20b |
| `illustrate.py reassemble` — rebuild prompts after editing the bible | **tested** |
| `gen.py`, `illustrate.py render` — SDXL int8 on the GPU, PNG + JSON sidecar, contact sheet | **tested**: 1024x1024, 25 steps, **~8.9 s per image** once warm (first image ~11 s; one-time model load ~16 s) |
| Character consistency across scenes | **partial** (see below) |

### First consistency test (example story, 3 scenes x 2 variants, one run)

- **Held:** the clothing (green coat appears in every image with Mara), the old harbourmaster
  (white beard, dark coat, same desk-and-clocks room in both variants), and the overall ink and
  watercolor look. Pinned location shots worked (wide establishing shots where requested).
- **Did not hold:** Mara's hair. The bible says "short dark braid"; the six images show a dark bun,
  a dark ponytail, no figure at all (one variant of scene 3 omitted her), and an orange-blond
  woman. No image shows a braid. Faces cannot be compared (back views and small figures).
- **Other defects:** a yellow tint bled from the lantern onto the pier planks in one image, and the
  scene 3 prompt was 56 words (over the ~55 ceiling) while those images are visibly more saturated
  than the "muted" style asked for; that is consistent with the style tail being cut off, but it
  was not isolated.
- **Implication:** plain-text character descriptions fix *clothing and props* well but not *hair or
  face*. Options, in order of effort: make characters identifiable by strong simple features (a
  vivid garment colour, a distinctive prop, a hair colour that is repeated); shorten prompts; train a
  small LoRA per main character (the pipeline accepts adapters).

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
