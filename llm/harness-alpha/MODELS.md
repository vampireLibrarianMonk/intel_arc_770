# Model registry — Arc A770 harness

Single place for what is on disk in `artifacts/harness-alpha/models/` (git-ignored), where it
came from, how it performed, and whether it is worth keeping. Files stay in a flat directory
because every script resolves `$MODELS_DIR`; this document is the organisation layer.

Measured 2026-11-06 on: Arc A770 16 GiB (`8086:56a0`), kernel 7.0.0-42 (i915), Mesa 25.2.8 ANV,
llama.cpp Vulkan (`-ngl 999`, ctx 4096, greedy). Raw data: `reports/data/tuning-24.04-kernel7.0/`.

## Models on disk (all Q4_K_M GGUF, all sha256-verified)

| model | role | size GiB | pp512 t/s | tg128 t/s | eff. GB/s¹ | hard coding | hard writing | verdict |
|:--|:--|--:|--:|--:|--:|:--:|:--:|:--|
| Qwen2.5-14B-Instruct | best quality | 8.37 | 529 | 22.7 | 204 | **5/5** | 3/5 | **keep** — only model to pass all hard coding tasks |
| Meta-Llama-3.1-8B-Instruct | speed/writing balance | 4.58 | 964 | 42.6 | 210 | 4/5 | 3/5 | **keep** — matches 14B writing at ~2x speed |
| Qwen2.5-7B-Instruct | baseline / spec-decode target | 4.36 | 967 | 43.6 | 204 | 4/5 | 2/5 | **keep** — reference for all history in this repo |
| Phi-3.5-mini-instruct | speed floor | 2.23 | 1463 | 77.6 | 186 | 3/5 | 2/5 | keep — 2.2 GiB, cheap |
| DeepSeek-Coder-V2-Lite (16B MoE) | MoE speed reference | 9.65 | 1414 | 63.5 | n/a² | 4/5 | 0/5 | keep for now — revisit once gpt-oss-20b is scored |
| Qwen2.5-Coder-7B-Instruct | coding specialist | 4.36 | n/a³ | 41.8³ | n/a | 4/5 | 3/5 | prune candidate — ties the general 7B on coding |
| gemma-2-9b-it | tidy prose | 5.36 | 712 | 27.4 | 158 | 3/5 | 2/5 | **prune candidate** — slower and no better than Llama-3.1-8B |
| Mistral-Nemo-Instruct-2407 (12B) | long-context writer | 6.96 | 641 | 27.7 | 207 | 4/5 | 1/5 | **prune candidate** — slower and worse writing than Llama-3.1-8B |

¹ `tg128 x file bytes`: bytes of weights streamed per second. Ignores KV cache/activations, so
it is a rough effective-bandwidth figure, not a profiler reading. Dense models cluster at
~200 GB/s regardless of size, which is why generation speed scales inversely with file size.
² MoE reads only the active experts per token, so this figure is not comparable.
³ Not run through `llama-bench`; 41.8 tok/s is the harness median (different method).

Hard-set scores are single greedy runs over 5 coding + 5 writing tasks, so **one-task gaps are
within noise** and rankings between neighbours (e.g. 4/5 vs 3/5) are weak evidence. Details and
per-task failures: `reports/alt_models_comparison.md`.

Prune candidates total ~16.7 GiB. Nothing has been deleted; re-downloading costs hours at the
~0.3-0.6 MiB/s uplink, so only prune when disk is actually needed.

## Recommended configurations (measured — see `reports/followup_techniques.md`)

| use | model + flags | tok/s |
|:--|:--|--:|
| best quality (coding) | Qwen2.5-14B + `--spec-type draft-simple -md Qwen2.5-0.5B-Instruct-Q8_0.gguf --spec-draft-ngl 999 --spec-draft-n-max 3` | ~32 |
| fast writing / general | Meta-Llama-3.1-8B, default flags | ~42 |
| fastest usable | DeepSeek-Coder-V2-Lite (coding only — fails writing constraints) | ~59 |
| long prompts (~8K+ tokens) | any of the above + `-fa off --cache-ram 0` | 31-40% faster responses at ~11K tokens |

`-fa off` must be paired with `--cache-ram 0`. On its own it halves harness throughput: the
host-RAM prompt cache takes 2-3 s per request to save/restore without flash attention.

## Auxiliary files

| file | purpose | source | status |
|:--|:--|:--|:--|
| Qwen2.5-0.5B-Instruct-Q8_0.gguf | draft model for speculative decoding of the Qwen2.5 7B/14B | bartowski/Qwen2.5-0.5B-Instruct-GGUF | on disk, verified |
| eagle3-gpt-oss-20b-Q8_0.gguf | EAGLE3 draft head for gpt-oss-20b | ggml-org/gpt-oss-20b-GGUF | on disk, verified |
| gpt-oss-20b-MXFP4.gguf | 20B MoE (~3.6B active), 12.1 GB; leading 16 GB candidate | ggml-org/gpt-oss-20b-GGUF | **downloading** (`.part`), then unscored |

## Integrity

Authoritative sizes/sha256 come from Hugging Face LFS metadata and are pinned in
`run_model_sweep.sh`, `run_alt_models.sh` and `setup/fetch_followup_models.sh`. Local checksums
were recomputed on 2026-11-06 and all eight matched. Verify any time with:

```bash
cd artifacts/harness-alpha/models && sha256sum -c SHA256SUMS
```

`SHA256SUMS` lives next to the models (git-ignored); regenerate with
`sha256sum *.gguf > SHA256SUMS`.

## Re-fetching

```bash
bash llm/harness-alpha/run_alt_models.sh vulkan             # all five non-Qwen rows
bash llm/harness-alpha/setup/fetch_followup_models.sh       # draft / eagle3 / gpt-oss-20b
```

Both use the sha256-gated resumable fetcher; `HF_TOKEN` is optional and never logged. Note the
token does not speed downloads: the cap is the local uplink (measured the same against a
non-HF server).
