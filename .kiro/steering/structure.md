# Structure steering — arc-a770-lab

## Folder layout

```text
arc-a770-lab/
├── README.md                     # Entry point
├── AGENTS.md                     # Always-on guardrails
├── .kiro/
│   ├── steering/                 # product.md, tech.md, structure.md
│   ├── specs/                    # one folder per phase (requirements/design/tasks)
│   └── skills/                   # later: experiment-runner skill
├── docs/
│   ├── STRATEGY.md               # full strategy (canonical)
│   ├── REPOSITORIES.md           # repo map + pinned SHA table
│   ├── EXPERIMENT_TEMPLATE.md    # hypothesis/controls/results record
│   └── ADR/                      # architecture decision records
├── tests/
│   ├── opencl/                   # C++17 API tests and kernels
│   ├── level-zero/               # follow-on tests
│   ├── pytorch/                  # PyTorch / XPU application harness
│   └── oracles/                  # independent CPU references
├── benchmarks/{workloads,manifests}
├── scripts/                      # capture_baseline.sh, setup_sources.sh, run_matrix.py
├── src/                          # harness helpers / optional policy experiments
├── patches/                      # small reviewable diffs, never modify vendor by default
├── vendor/                       # git-ignored upstream clones
├── artifacts/                    # git-ignored bulky logs and raw outputs
└── reports/                      # reviewed results and plots
```

## Naming conventions

- Test IDs: `MEM-01`..`MEM-10` for the allocation matrix; backlog IDs `ARC-001`..`ARC-013`.
- Experiment records: `ARC-MEM-NNNN` with a paired Markdown + JSON file.
- Benchmark manifests: one YAML per fixed workload + parameter set, versioned.

## Quality gates

- Every correctness claim is checked against an independent CPU oracle.
- Sentinels must cross the 4 GiB byte offset (around `2^32-1`, `2^32`, `2^32+4096`).
- Allocation success alone is never evidence of correctness.
- Every patch links to an experiment, passes the original reproducer and regression tests,
  and includes pre/post measurements with software versions and raw samples.
- A speedup with incorrect results is a failed patch.

## Where things go

- Durable policy → `.kiro/steering/` and `AGENTS.md`.
- Phase decomposition → `.kiro/specs/<phase>/{requirements,design,tasks}.md`.
- Raw/bulky output → `artifacts/` (git-ignored). Reviewed output → `reports/`.
- Upstream clones → `vendor/` (git-ignored); never modified in place by default.
