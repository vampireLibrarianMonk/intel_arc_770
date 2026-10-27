# Addressing Performance Study — Design

## Components
- `benchmarks/workloads/` — one subdir per workload class (addrgen, stream, random, compute, segmented).
- `benchmarks/manifests/` — one YAML per fixed workload+params (sizes 2/6/8 GiB, seeds, dims).
- `scripts/run_matrix.py` — orchestrates A/B runs, collects raw samples, writes to `artifacts/`.
- Integration with `intel/compute-benchmarks` for cross-checking.

## Measurement harness
- Warm-up iterations discarded.
- >= 10 (prefer 20) timed reps; A/B order randomized per rep.
- Separate timers: H2D, kernel, D2H, buffer creation, compile.
- Stats: median, p95, IQR/stddev; persist all raw samples (CSV/JSON).

## Reporting
- `reports/` gets reviewed plots + summary; `artifacts/` holds raw.
- Each result ties to an experiment record (see `docs/EXPERIMENT_TEMPLATE.md`).

## Guardrails
- Flag non-equivalent algorithm variants explicitly.
- Abort and flag on hang/reset; never overwrite raw samples.
