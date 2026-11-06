#!/usr/bin/env bash
# run_ov_followup.sh — does OpenVINO int4's speed advantage carry over to bigger models?
#
# For each candidate IR: fetch it (sha256-gated for the weights), measure steady-state GPU
# generation speed with ov_sweep.py (default config), and compare against llama.cpp Vulkan
# tg128 for the same model on this card. Only if OpenVINO is >= GATE x faster is the model
# marked eligible for eval-v2 (writes GATE_PASS in its directory). Then it is also scored on
# the harness-alpha hard set for continuity.
#
# Runs after the main download chain (run_pending_evals.sh) so it never splits the uplink.
# Progress: artifacts/harness-alpha/OV_FOLLOWUP_STATUS.txt
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"
STATUS="$PREFIX/OV_FOLLOWUP_STATUS.txt"
OVM="$REPO_ROOT/artifacts/ov-models"
PY="$REPO_ROOT/.venv-ov/bin/python"
GATE="${GATE:-1.2}"
note() { printf '%s | %s\n' "$(date '+%F %T')" "$*" | tee -a "$STATUS"; }

# repo | weights size | weights sha256 | Vulkan tg128 baseline for the same model (tok/s, measured)
ROWS=(
  "OpenVINO/Qwen2.5-14B-Instruct-int4-ov|8373190236|40d0b0469572492737cfac25e11189d34bd57db3bc20ee84014c0c36860317f9|22.68"
)

note "ov-followup started (pid $$, gate ${GATE}x)"
if [ "${SKIP_WAIT:-0}" != 1 ]; then
  until grep -q "pending-evals COMPLETE" "$PREFIX/PENDING_STATUS.txt" 2>/dev/null; do sleep 120; done
  note "main download chain complete"
fi

for row in "${ROWS[@]}"; do
  IFS='|' read -r repo size sha base <<< "$row"
  name="${repo#*/}"; dir="$OVM/$name"; mkdir -p "$dir"
  note "=== $name ==="
  # small files (configs, tokenizer IR): plain resumable fetch
  for f in $(curl -s "https://huggingface.co/api/models/$repo/tree/main" | python3 -c \
      "import sys,json;[print(x['path']) for x in json.load(sys.stdin) if x['path']!='openvino_model.bin']"); do
    [ -s "$dir/$f" ] || curl -fsSL --retry 5 -o "$dir/$f" "https://huggingface.co/$repo/resolve/main/$f" \
      || note "$name: failed to fetch $f"
  done
  if [ ! -f "$dir/openvino_model.bin" ]; then
    bash "$HA_DIR/setup/get_model_generic.sh" "$repo" openvino_model.bin "$size" "$sha" \
      >> "$LOG_DIR/fetch_ov_$name.log" 2>&1 && mv "$MODELS_DIR/openvino_model.bin" "$dir/" \
      || { note "$name: weights FETCH FAILED"; continue; }
  fi
  note "$name: weights verified; measuring speed"
  "$PY" "$HA_DIR/ov_sweep.py" "$dir" default > "$LOG_DIR/ov_gate_$name.jsonl" 2>&1
  verdict=$(python3 - "$LOG_DIR/ov_gate_$name.jsonl" "$base" "$GATE" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.startswith("{")]
r = next((x for x in rows if "tok_s" in x), None)
if not r:
    print("FAIL no-measurement"); sys.exit()
ov = sum(r["tok_s"]) / len(r["tok_s"]); base = float(sys.argv[2]); ratio = ov / base
print(("PASS" if ratio >= float(sys.argv[3]) else "FAIL") + f" openvino={ov:.1f} vulkan={base} ratio={ratio:.2f}x")
PY
)
  note "$name: gate $verdict"
  if [[ "$verdict" == PASS* ]]; then
    echo "$verdict" > "$dir/GATE_PASS"
    OV_MODEL="$dir" CANDIDATE_SUFFIX="-int4-${name%%-Instruct*}" TASK_SET=hard \
      timeout 3600 bash "$HA_DIR/run/run_openvino.sh" >> "$LOG_DIR/ov_hard_$name.log" 2>&1 \
      && note "$name: hard set OK" || note "$name: hard set FAILED"
  fi
done
note "ov-followup COMPLETE"
