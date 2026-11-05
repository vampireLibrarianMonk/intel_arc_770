# Next session — pick up here

## Fast path with your HF token

The remaining model downloads were crawling on a throttled anonymous HF mirror (~0.3 MiB/s).
With a token they'll be fast. Set it, then re-run the alt-models sweep — the fetcher is
sha256-gated and idempotent, so anything already downloaded is skipped and only the missing
models are pulled.

```bash
cd ~/projects/intel_arc_770
export HF_TOKEN=hf_xxx            # your token
# curl picks up the auth header via ~/.netrc or an Authorization header; simplest is:
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
bash llm/harness-alpha/run_alt_models.sh vulkan      # hard set by default
tail -f artifacts/harness-alpha/ALT_STATUS.txt
```

NOTE: `setup/get_model_generic.sh` currently fetches anonymously (public repos, no auth
header). If a token is needed for speed/rate-limits, add `-H "Authorization: Bearer $HF_TOKEN"`
to its `curl` line — one-line change. All five target repos are public, so a token mainly buys
throughput/rate-limit headroom, not access.

## What's already done (committed + pushed to master)

- Reboot verified on kernel 7.0.0-42; Vulkan baseline holds at ~41 tok/s (glslc fix survived).
- Flag tuning matrix: no lever beats defaults (negative result).
- GPU clock/power: A770 already pins 2400 MHz under load, zero throttle — not a lever.
- Model sweep (Qwen): 7B/Coder-7B 42 tok/s, 14B 22 tok/s. Parameter count is the speed lever.
- Hard discriminating task set built; exposed + fixed a harness hang (exec-timeout watchdog).
- Non-Qwen results so far: **Llama-3.1-8B** (42 tok/s, hard 4/5 coding + 3/5 writing — matches
  Qwen-14B writing at 2x speed) and **Phi-3.5-mini** (76.8 tok/s, 3/5 + 2/5).

## Still pending (downloading overnight, async via run_alt_models.sh)

- gemma-2-9b-it (5.8 GB) — tidy-prose writer
- Mistral-Nemo-Instruct-2407 12B (7.5 GB) — writing, 128K ctx, anti-slop
- DeepSeek-Coder-V2-Lite 16B MoE (10.4 GB) — coding specialist; MoE may beat dense curve

When they finish: copy their `artifacts/harness-alpha/llamacpp-vulkan-*_*.json` into
`reports/data/tuning-24.04-kernel7.0/`, fill the pending rows in
`reports/alt_models_comparison.md`, update CHANGELOG, commit + push.

## Open track (needs your call)

- **SYCL re-test on kernel 7.0** — requires installing oneAPI DPC++ (multi-GB, touches system
  library paths → AGENTS.md human-approval gate). Prior cycle showed SYCL slower than Vulkan
  (33.9 vs 40.2), so low expected value. Skip unless you want it.
