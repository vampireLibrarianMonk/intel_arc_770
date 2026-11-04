# Tuning cycle data — Ubuntu 24.04 / kernel 7.0.0-42

Raw results from the Vulkan tuning matrix, kept in-repo (gitignored `artifacts/` is
ephemeral). Small JSON, verbatim model output included for human quality review, no secrets.

- `env.txt` — kernel, GPU/driver, Vulkan device, glslc, groups at capture time.
- `llamacpp-vulkan_POST-REBOOT-baseline_*.json` — verified baseline after the kernel 7.0
  reboot (median 41.0 tok/s), confirming the glslc regression fix (commit `940e691`) held.
- `llamacpp-vulkan-<variant>_*.json` — one file per tuning lever; see
  `reports/tuning_matrix_plan.md` for flags, hypotheses, and the results table.

## Headline

No lever beat the default flags. `-fa on` and ubatch resizing were within noise; 8-bit KV
cache (`-ctk/-ctv q8_0`) cost ~1.5 tok/s. Default llama.cpp Vulkan flags are already
near-optimal for 7B-Q4 at 4K context on the A770. Full analysis + next tracks in
`reports/tuning_matrix_plan.md`.

## Reproduce

```bash
cd ~/projects/intel_arc_770
bash llm/harness-alpha/run_tuning_matrix.sh vulkan
python3 llm/harness-alpha/aggregate.py
```
