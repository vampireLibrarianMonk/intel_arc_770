# Baseline Inventory — Design

## Components
- `scripts/capture_baseline.sh` — read-only discovery; writes raw logs + `environment.json`.
- Optional `clinfo` / `ze_info` parsing into JSON (skipped gracefully if absent).

## Data flow
1. Collect `uname`, `/etc/os-release`, `lspci -nnk`, `/dev/dri` listing, `lsmod`.
2. Query `clinfo` for device name, global mem, max alloc (if installed).
3. Query `ze_info` (if installed).
4. Scrape `journalctl -k` for `i915|xe|drm|guc|hang|reset`.
5. Emit raw text to `artifacts/baseline/<timestamp>/` and a merged `environment.json`.

## environment.json schema (draft)
```json
{
  "captured_at": "ISO-8601",
  "host": {"os": "", "kernel": "", "modules": []},
  "gpu": {"model": "", "pci_id": "", "render_nodes": [], "rebar": "", "pcie_link": ""},
  "opencl": {"icd": "", "device_name": "", "global_mem_bytes": 0, "max_alloc_bytes": 0},
  "level_zero": {"loader": "", "present": false},
  "versions": {"neo": "", "igc": "", "gmmlib": ""},
  "permissions": {"render_node_rw": false},
  "notes": []
}
```

## Error handling
- Every probe is best-effort (`|| true`); absence is recorded, not fatal.
- No command requires sudo. If a value needs privilege, record it as `"unavailable_without_privilege"`.
