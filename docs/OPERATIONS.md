# Operations runbook — arc-a770-lab (on-hardware bring-up)

**Host:** `intelgpuserver` · Ubuntu 22.04.5 · kernel 5.15.0-119-generic
**GPU:** Intel Arc A770 `8086:56a0` at PCI `2d:00.0` (confirmed present)
**Prepared:** 2026-10-30

This runbook governs the live bring-up of the A770 so the PyTorch/XPU harness can run.
It extends `AGENTS.md` and `.kiro/steering/tech.md`; where they conflict, safety wins.

---

## Operating reality (who runs what)

The Kiro agent shell on this host is **unprivileged**:

- `sudo` is disabled — `no-new-privileges` is set and `/etc/sudo.conf` is owned by `nobody`.
- System dirs (`/etc/apt/...`) are owned by `nobody:nogroup`; the agent cannot write them.
- `apt-get` real execution is refused; only `--dry-run` works.

**Therefore:** the agent plans, writes scripts, and verifies. **The human operator runs every
privileged step in a real root/sudo shell.** The agent never claims an install happened; it
re-runs the read-only probes afterward and reports what actually changed.

### Agent may (no approval needed)
- Read-only discovery: `lspci`, `lsmod`, `ls /dev/dri`, `clinfo`, `ze_info`, `apt-cache`, `--dry-run`.
- Run repo scripts that change nothing: `check_prereqs.sh`, `check_pytorch_xpu.py`, `capture_baseline.sh`.
- Write/edit files inside `~/projects/intel_arc_770`.
- Build/run the C++ and Python harnesses once a render node exists.

### Human-approval-required (operator runs, agent only drafts)
- Any `apt-get install` / `add-apt-repository` / writing `/etc/apt/sources.list.d/*`.
- Installing or upgrading a kernel; installing dkms modules.
- `modprobe` / module bind/unbind; anything under `/etc/modprobe.d`.
- Adding a user to a group; changing `/dev/dri` permissions.
- Any BIOS/ReBAR/bootloader/firmware change.

### Hard stop (do not proceed without explicit go-ahead)
- GPU hang/reset, thermal alarm, data-corruption signal, kernel panic, host instability.

---

## Reboot policy

A reboot is required after: installing a new kernel, installing the i915 backport dkms,
or a firmware/ReBAR/BIOS change. The agent will say **"RESTART REQUIRED"** on its own line
before any step whose effect only lands after reboot, and will pause there.

---

## Root cause (why the GPU is unusable today)

Chain, each link verified by read-only probe:

1. A770 is DG2/Alchemist; PCI id `8086:56a0`.
2. The loaded `i915` (kernel 5.15) has **no `56a0` alias** — too old for DG2.
3. i915 loads but **never binds** to the card (no "Kernel driver in use" line in `lspci -k`).
4. No bind → **no `/dev/dri/renderD128`**.
5. No render node → Level Zero / OpenCL / `torch.xpu` have no device to open.

Fixing link 2 (newer i915) is the unlock; everything else follows.

---

## Blocker tracker

See `docs/BRINGUP_STATUS.md` — the single source of truth for what is done, in progress,
and blocked. Update it after every step.

---

## Bring-up sequence (high level)

1. **B1 — Kernel/i915 with A770 support.** Either boot an installed HWE/OEM 6.x kernel, or add
   Intel's client-GPU repo and install the i915 backport dkms. *RESTART REQUIRED.*
2. **B2 — Render node + permissions.** Confirm `/dev/dri/renderD128` appears and the user is in
   the `render` group.
3. **B3 — Compute user-space.** Install `intel-opencl-icd`, `libze-intel-gpu`, `level-zero`,
   `clinfo`. Verify with `clinfo` and `ze_info`.
4. **B4 — PyTorch/XPU.** Install an XPU-enabled torch (oneAPI build) in a venv. Verify with
   `scripts/check_pytorch_xpu.py`.
5. **B5 — Baseline capture.** Run `capture_baseline.sh`, archive `environment.json`.
6. **B6 — Hand off to Phase 1** (4 GiB boundary harness) and Phase 2 (perf).

Each blocker gets its own draft script under `scripts/bringup/` for the operator to review and run.
