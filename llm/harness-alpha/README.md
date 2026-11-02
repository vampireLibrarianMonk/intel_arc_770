# Harness alpha cycle — Arc A770

# Harness alpha cycle — Arc A770

Goal: find a CLI/local inference harness that is good for **creative writing assistance**
and **coding assistance** on the Intel Arc A770, judged by real runs on this card — not by
blog claims.

## Results (all four candidates ran; see `reports/harness_alpha_comparison.md`)

| candidate | backend | coding (executed) | writing | median tok/s |
|:--|:--|:--:|:--:|--:|
| **llamacpp-vulkan** | Vulkan | 4/4 | 4/4 | **40.2** |
| lmstudio | Vulkan | 4/4 | 4/4 | 37.4 |
| llamacpp-sycl | SYCL | 4/4 | 4/4 | 33.9 |
| ipex-llm | XPU | 3/4 | 4/4 | 16.6 |

**Recommendation: llama.cpp Vulkan** — fastest, stable, scriptable. LM Studio is the
friendlier-UX option on the same backend. SYCL needed two bug workarounds to stop crashing
(see `reports/sycl_fix_plan.md`) and ends up slower than Vulkan once stable. IPEX-LLM is the
stable native-XPU fallback. Writing quality is comparable across backends (same model); pick
on speed + UX.

## The candidates

| id | harness | Arc GPU backend | why it's in the alpha |
|:--|:--|:--|:--|
| `llamacpp-sycl`  | llama.cpp (SYCL build)   | SYCL (native) | performance reference — fastest documented Arc path |
| `llamacpp-vulkan`| llama.cpp (Vulkan build) | Vulkan        | shared-backend baseline; no oneAPI needed |
| `lmstudio`       | LM Studio (`lms` CLI + server) | Vulkan   | best UX; the one with a GUI + model manager |
| `ipex-llm`       | our existing Python harness | XPU (IPEX-LLM) | incumbent control, already working |

`llamacpp-vulkan`, `lmstudio` share the **same Vulkan compute backend**, so comparing them
isolates "does the UX/packaging matter" from "does the backend matter". `llamacpp-sycl` vs
`llamacpp-vulkan` isolates SYCL-vs-Vulkan on identical code + model.

## The three claims we never conflate (from AGENTS.md)

1. **It ran on the GPU** — VRAM actually allocated, not a silent CPU fallback.
2. **Output is correct / usable** — coding scored by executing against tests; writing
   checked for measurable properties AND saved verbatim for human judgement.
3. **It was fast** — tokens/sec, repeatable.

A harness that is fast but silently on CPU, or fast but wrong, is not a win.

## Layout

```
llm/harness-alpha/
├── README.md              # this file
├── bench_openai.py        # shared driver: scores any OpenAI-compatible endpoint
├── tasks.py               # the coding + creative-writing task set (shared, fixed)
├── score.py               # execution-based coding scorer + writing property checks
├── gpu_probe.sh           # confirm a run actually used the A770 (VRAM / engine busy)
├── setup/                 # one setup script per candidate (local prefixes, no sudo)
│   ├── common.sh
│   ├── get_model.sh       # fetch the shared GGUF once
│   ├── llamacpp_sycl.sh
│   ├── llamacpp_vulkan.sh
│   └── lmstudio.sh
└── run/                   # one runner per candidate; each starts a server then calls bench
    ├── run_llamacpp.sh     # arg: sycl | vulkan
    ├── run_lmstudio.sh
    ├── run_ipex.sh
    └── ipex_server.py      # OpenAI-compatible shim over IPEX-LLM
```

Raw per-run output → `artifacts/harness-alpha/` (git-ignored).
Reviewed comparison → `reports/` + a `docs/` experiment record.

## How to run (durable; survives shell/session exit)

Downloads and benchmarks are launched as **systemd user units** so they survive disconnects
and can be monitored cheaply. Check progress anytime with `bash llm/harness-alpha/status.sh`.

```bash
cd ~/projects/intel_arc_770

# 1. fetch prerequisites (shared GGUF + 7B HF weights + oneAPI DPC++ compiler), self-healing
systemd-run --user --unit=ha-fetch --working-directory="$PWD" bash llm/harness-alpha/fetch_all.sh
bash llm/harness-alpha/status.sh          # poll until GGUF DONE / icpx READY / 7B-HF DONE

# 2. build the llama.cpp backends (needs: libvulkan-dev+glslc+spirv-headers for Vulkan;
#    oneAPI DPC++ + oneDNN + oneMKL for SYCL — see reports/sycl_fix_plan.md for apt packages)
bash llm/harness-alpha/setup/llamacpp_vulkan.sh
bash llm/harness-alpha/setup/llamacpp_sycl.sh

# 3. run every ready candidate, sequentially, skipping any not yet buildable
systemd-run --user --unit=ha-run --working-directory="$PWD" bash llm/harness-alpha/run_all.sh
tail -f artifacts/harness-alpha/RUN_STATUS.txt

# 4. aggregate the four-way comparison
python llm/harness-alpha/aggregate.py     # prints the table, writes combined.json
```

To run a single candidate directly (also fine):
`bash llm/harness-alpha/run/run_llamacpp.sh vulkan` (or `sycl`), `run_lmstudio.sh`, `run_ipex.sh`.

### SYCL-specific requirements (learned the hard way)

The SYCL build + run needs these non-obvious settings, baked into the scripts:
- build: `-DGGML_SYCL_SUPPORT_LEVEL_ZERO_API=OFF -DGGML_SYCL_DNN=OFF`
- run: `SYCL_CACHE_PERSISTENT=0`

Without them, llama.cpp SYCL **segfaults** on NEO 24.39 + oneAPI 2026.2. Full root-cause
analysis and the path to a complete fix: `reports/sycl_fix_plan.md`.

## Shared model

All GGUF candidates use ONE model so results are apples-to-apples. Default:
`Qwen2.5-7B-Instruct` Q4_K_M (coding + writing capable, fits 16 GiB with room for context).
Fetched once by `setup/get_model.sh` into `artifacts/harness-alpha/models/` (git-ignored).

IPEX-LLM uses the HF-format equivalent (`Qwen/Qwen2.5-7B-Instruct`, 4-bit) — not identical
bytes, but the same model family/size, and that difference is noted in the report.
