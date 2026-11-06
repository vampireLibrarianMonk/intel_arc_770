# Next session — pick up here

## State (2026-11-06, afternoon)

- Registry + recommended configs: `llm/harness-alpha/MODELS.md`. Full findings:
  `reports/followup_techniques.md`.
- Intel compute runtime installed (NEO 26.40 / IGC 2.42.6 / L0 1.34.0) with approval;
  OpenVINO GenAI sees the A770. On identical GGUF weights it is ~5-10% slower than Vulkan.
- `-fa off` mystery solved: pair it with `--cache-ram 0`. It's a 31-40% win on long prompts.

## Running unattended

`ha-pending` (systemd user unit) runs `llm/harness-alpha/run_pending_evals.sh`:
1. waits for `openvino_model.bin` of `OpenVINO/Qwen2.5-7B-Instruct-int4-ov` (unit `ha-ov-bin`,
   4.46 GB at ~0.35 MiB/s, ~3.5 h from 15:15 UTC), then scores it on the hard set and runs the
   OpenVINO config sweep;
2. then fetches gpt-oss-20b MXFP4 (11.5 GB left, ~9-10 h), scores it at `--reasoning-effort
   low` with and without EAGLE3, and runs llama-bench.

Check: `cat artifacts/harness-alpha/PENDING_STATUS.txt`

## When it finishes

- Copy `artifacts/harness-alpha/openvino-gpu-int4-7b_*.json`,
  `llamacpp-vulkan-gptoss20b*_*.json`, `logs/ov_sweep_int4_7b.jsonl`,
  `logs/llama_bench_gptoss20b.md` into `reports/data/tuning-24.04-kernel7.0/`.
- Fill §6 (int4) and §4 (gpt-oss) in `reports/followup_techniques.md`, and add rows to
  `MODELS.md`. For gpt-oss, read the raw outputs: a reasoning model can run out of the
  512-token budget before answering, which would be a harness artifact, not a quality result.

## Not run, by choice

- llama.cpp SYCL: Vulkan is faster here and upstream agrees; needs a multi-GB oneAPI download.
- `xe` kernel driver: needs a reboot with kernel parameters changed, so do it while present.
