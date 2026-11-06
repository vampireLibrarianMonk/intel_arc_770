#!/usr/bin/env bash
# run_pending_evals.sh — unattended chain for the download-gated evaluations.
#
#   1. wait for the OpenVINO int4 IR of Qwen2.5-7B (fetched by unit ha-ov-bin), then score it
#      through the shared harness on the GPU and run the OpenVINO config sweep on it;
#   2. fetch gpt-oss-20b (MXFP4) + EAGLE3 head (sha256-gated, resumable), then score it with and
#      without EAGLE3 speculative decoding, plus llama-bench pp/tg.
# Downloads run one at a time on purpose: the uplink is ~0.3-0.6 MiB/s and splitting it only
# delays the first result. Progress: artifacts/harness-alpha/PENDING_STATUS.txt
set -uo pipefail
HA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HA_DIR/setup/common.sh"
STATUS="$PREFIX/PENDING_STATUS.txt"
note() { printf '%s | %s\n' "$(date '+%F %T')" "$*" | tee -a "$STATUS"; }
OV_DIR="$REPO_ROOT/artifacts/ov-models/Qwen2.5-7B-Instruct-int4-ov"
OSS="$MODELS_DIR/gpt-oss-20b-MXFP4.gguf"
EAGLE="$MODELS_DIR/eagle3-gpt-oss-20b-Q8_0.gguf"

note "pending-evals started (pid $$)"

# ---- 1. OpenVINO native int4 ----
note "waiting for $OV_DIR/openvino_model.bin"
for _ in $(seq 1 2880); do [ -f "$OV_DIR/openvino_model.bin" ] && break; sleep 30; done
if [ -f "$OV_DIR/openvino_model.bin" ]; then
  note "OV int4 present; scoring through harness"
  OV_MODEL="$OV_DIR" CANDIDATE_SUFFIX=-int4-7b TASK_SET=hard \
    timeout 2400 bash "$HA_DIR/run/run_openvino.sh" >> "$LOG_DIR/ov_int4_7b.log" 2>&1 \
    && note "OV int4 harness: OK" || note "OV int4 harness: FAILED (logs/ov_int4_7b.log)"
  "$REPO_ROOT/.venv-ov/bin/python" "$HA_DIR/ov_sweep.py" "$OV_DIR" \
    > "$LOG_DIR/ov_sweep_int4_7b.jsonl" 2>&1 && note "OV int4 sweep: OK" || note "OV int4 sweep: FAILED"
else
  note "OV int4 never arrived — skipped"
fi

# ---- 2. gpt-oss-20b ----
note "fetching gpt-oss-20b + EAGLE3"
bash "$HA_DIR/setup/fetch_followup_models.sh" >> "$LOG_DIR/followup_nohup.log" 2>&1
if [ -f "$OSS" ]; then
  RE="--reasoning-effort low"
  for spec in "-gptoss20b|$RE" "-gptoss20b-eagle3|$RE --spec-type draft-eagle3 -md $EAGLE --spec-draft-ngl 999"; do
    suf=${spec%%|*}; fl=${spec#*|}
    [ "$suf" = "-gptoss20b-eagle3" ] && [ ! -f "$EAGLE" ] && { note "$suf: SKIP (no eagle3)"; continue; }
    CANDIDATE_SUFFIX="$suf" LLAMACPP_MODEL="$OSS" TASK_SET=hard LLAMACPP_EXTRA_FLAGS="$fl" \
      timeout 2400 bash "$HA_DIR/run/run_llamacpp.sh" vulkan >> "$LOG_DIR/alt_${suf}.log" 2>&1 \
      && note "$suf: OK" || note "$suf: FAILED (logs/alt_${suf}.log)"
  done
  "$BUILD_DIR/llama.cpp/build-vulkan/bin/llama-bench" -m "$OSS" -ngl 999 -p 512 -n 128 -d 0,4096,16384 -r 2 -o md \
    > "$LOG_DIR/llama_bench_gptoss20b.md" 2>&1 && note "gpt-oss llama-bench: OK" || note "gpt-oss llama-bench: FAILED"
else
  note "gpt-oss-20b not verified — skipped (see logs/fetch_followup.log)"
fi
note "pending-evals COMPLETE"
