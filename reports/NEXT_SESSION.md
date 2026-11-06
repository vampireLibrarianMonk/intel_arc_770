# Next session — pick up here

## State (2026-11-06)

- All eight on-disk models are scored on the hard set and sha256-verified; see
  `llm/harness-alpha/MODELS.md` for the registry and recommended configs.
- Follow-up audit done: `reports/followup_techniques.md`. Headline: speculative decoding makes
  Qwen2.5-14B 21.5 → 31 tok/s. Matrix cores on the A770 are a 10x prefill regression (negative).

## Running unattended

- `ha-followup-fetch` (systemd user unit): downloading `gpt-oss-20b-MXFP4.gguf` (12.1 GB,
  ~0.3 MiB/s, roughly 10 h from 13:40 UTC 2026-11-06). The EAGLE3 head and 0.5B draft are
  already on disk.
  Check: `ls -la artifacts/harness-alpha/models/ | grep gpt-oss` and
  `tail artifacts/harness-alpha/logs/fetch_followup.log`.

## To do

1. When gpt-oss-20b lands: benchmark it on the hard set, then again with
   `--spec-type draft-eagle3 -md eagle3-gpt-oss-20b-Q8_0.gguf`. Add rows to `MODELS.md`. Note
   it is a reasoning model, so check that its output channel parses cleanly in `bench_openai.py`.
2. **Needs your approval:** Intel compute runtime (NEO + Level Zero) so OpenVINO GenAI
   (already in `.venv-ov`) can use the GPU. Prefer a container/local prefix; Ubuntu's
   `intel-opencl-icd` 23.43 is old.
3. Investigate why `-fa off` halves `llama-server` generation when llama-bench says it should
   help.
4. Optional: Qwen3.5-9B; prune gemma-2-9b / Mistral-Nemo if disk gets tight (~12 GiB).
