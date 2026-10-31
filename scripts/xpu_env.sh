#!/usr/bin/env bash
# xpu_env.sh — enable full-VRAM (>4 GiB single allocation) for torch.xpu on the Arc A770.
#
# Usage, pick one:
#   source scripts/xpu_env.sh            # set the vars in your current shell
#   scripts/xpu_env.sh python train.py   # run a command with the vars set (no sourcing)
#   scripts/xpu_env.sh                    # no args: print the exports to copy
#
# Why: torch.xpu exposes no >4 GiB allocation flag, so a single tensor is capped at 4 GiB
# by default. NEO's AllowUnrestrictedSize debug key lifts that cap driver-wide. BOTH vars
# are required — AllowUnrestrictedSize alone does nothing without NEOReadDebugKeys.
#
# Caveat: AllowUnrestrictedSize is an Intel DEBUG key (dev/debug only, may be deprecated).
# Good for local large-tensor work; a shipping app should use the OpenCL/Level Zero API
# flags instead. See reports/FINDINGS_memory_4gib.md.

export NEOReadDebugKeys=1
export AllowUnrestrictedSize=1

# If sourced, we're done (vars are now in the caller's shell).
# $0 ends in "xpu_env.sh" only when executed, not sourced (bash/zsh differ; check both).
_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case $ZSH_EVAL_CONTEXT in *:file) _sourced=1;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  (return 0 2>/dev/null) && _sourced=1
fi

if [ "$_sourced" = "1" ]; then
  return 0 2>/dev/null
fi

# Executed directly:
if [ "$#" -gt 0 ]; then
  exec "$@"              # run the given command with the vars set
else
  echo "export NEOReadDebugKeys=1"
  echo "export AllowUnrestrictedSize=1"
  echo "# eval \"\$(scripts/xpu_env.sh)\"  to apply, or:  source scripts/xpu_env.sh"
fi
