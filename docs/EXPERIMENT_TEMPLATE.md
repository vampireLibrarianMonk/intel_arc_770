# Experiment record template

Every investigated finding is one Markdown record plus a machine-readable JSON/YAML file.
**Do not prefill `result` with success.** A speedup with incorrect results is a failed patch.

```yaml
experiment_id: ARC-MEM-0001
question: "Does supported OpenCL allocation >4 GiB preserve values beyond 2^32 bytes?"
hypothesis: "With both flags and sufficient memory, out-of-boundary sentinels match the CPU oracle."
hardware: {gpu: "Arc A770 16 GiB", pci_id: "TO_RECORD", rebar: "TO_RECORD"}
software: {ubuntu: "TO_RECORD", kernel: "TO_RECORD", neo: "TO_RECORD", igc: "TO_RECORD", gmmlib: "TO_RECORD"}
source: {runtime_sha: "TO_RECORD", compiler_sha: "TO_RECORD", harness_sha: "TO_RECORD"}
control: "stock driver; regular allocation; matching kernel"
candidate: "stock driver; relaxed allocation + stateless kernel build flag"
input: {buffer_size_bytes: "TO_RECORD", offsets_bytes: "TO_RECORD", seed: 123456}
validation: ["allocation status", "sentinels around 2^32", "device digest", "CPU reference"]
metrics: ["kernel_time_ms", "allocation_time_ms", "throughput_gbps", "gpu_reset_count"]
result: "PENDING — do not prefill success"
artifacts: ["raw API results", "driver logs", "test output", "CSV or JSON samples"]
```

## Narrative sections to include alongside the YAML

- **Context** — which hypothesis (H0–H3) and backlog ID (ARC-00x) this addresses.
- **Method** — exact reproduction command(s), flags, seeds, repetition count.
- **Evidence** — raw artifact paths; never summarize away the raw data.
- **Analysis** — median, p95, dispersion; distinguish policy limit vs resource exhaustion.
- **Classification** — app / OpenCL API / Level Zero / NEO / IGC / kernel / hardware.
- **Decision** — keep patch + document, or revert and revise hypothesis.
- **Limitations & uncertainty** — what was not verified.

## Patch acceptance checklist

- [ ] Links to an experiment record.
- [ ] Passes the original reproducer.
- [ ] Passes regression tests.
- [ ] Produces identical validated outputs (correctness unchanged).
- [ ] Includes pre/post measurements with software versions and raw samples.
