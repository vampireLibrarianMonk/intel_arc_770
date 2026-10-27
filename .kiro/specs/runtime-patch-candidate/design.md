# Runtime Patch Candidate — Design

## Approach
- Smallest falsifiable intervention tied to a specific experiment record.
- Candidate ordering (lowest risk first):
  1. Diagnostic warning when relaxed-allocation flag is set but stateless compile flag is missing
     (or vice versa) — the silent-corruption trap.
  2. Capability-query / adaptive strategy helper (`src/`) that picks a supported path per workload.
  3. Clearer user-facing error distinguishing allocation **policy** from **resource exhaustion**.
  4. Internal allocation-policy patch ONLY if a regression test demonstrates a real bug.

## Build & isolation
- Local-prefix NEO build; pinned manifest versions.
- Record loaded ICD path (`OCL_ICD_VENDORS`) / L0 loader; verify test used the built runtime.
- `patches/` holds small reviewable diffs; vendor tree not modified in place by default.

## Validation
- Re-run Phase 1 matrix + new regression test on both stock and patched runtime.
- Store pre/post measurements with SHAs and raw samples.

## Human-approval gates
Any system-wide install, module unbind, bootloader/kernel param, or firmware action pauses for
explicit approval per AGENTS.md.
