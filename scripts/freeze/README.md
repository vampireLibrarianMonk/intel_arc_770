# Freeze toolkit — time-capsule offline install

Capture a complete, timestamped, offline-installable snapshot of a **known-good A770 run**
so it can be reinstalled and reproduced in the far future without network access.

## When to run

**Only after YOU declare a run good.** The gate is manual by design: every script refuses
to run unless you pass `--i-say-so` and `--note="<which run>"`. There is no automated
"good run" detection — you are the authority.

## Three formats (run all via the orchestrator, or individually)

| Format | Script | Captures | Does NOT capture |
|:--|:--|:--|:--|
| **A1 bundle** | `freeze_python.sh`, `freeze_system.sh`, `freeze_source.sh` | pip wheels + lock, `.deb`s, git bundles | kernel (unless `--include-kernel`) |
| **A2 container** | `freeze_container.sh` | user-space stack as a loadable image tarball | host kernel / i915 driver |
| **A3 full image** | `freeze_image.sh` | kernel + i915 + user space (VM qcow2 or bare-metal guidance) | portability to different hardware |

## Quick start (on the A770 host, after a good run)

```bash
# Everything, one snapshot:
scripts/freeze/freeze_all.sh --i-say-so \
  --note="ARC-MEM-0007 green on A770, commit abc123"

# Lighter: skip the heavy full image, cache kernel debs in A1:
scripts/freeze/freeze_all.sh --i-say-so --note="..." --no-image --include-kernel

# Capture a powered-off VM as the A3 image:
scripts/freeze/freeze_all.sh --i-say-so --note="..." \
  --qcow2=/var/lib/libvirt/images/arc.qcow2 --powered-off
```

Snapshots land in `artifacts/freeze/<UTC-timestamp>/` (git-ignored).

## Rehearse first with `--dry-run`

Preview exactly what every layer would download, build, or image — without doing any of
it. Recommended before the first real freeze on a new host.

```bash
scripts/freeze/freeze_all.sh --i-say-so --note="rehearsal" --dry-run --guidance
```

`--dry-run` works on the orchestrator and every individual layer script. It still requires
the manual gate (`--i-say-so` + `--note`). It prints `[would]` lines for each action and
writes no wheels, `.deb`s, bundles, images, or checksum manifests. It is also a useful
probe: it reports which candidate apt packages actually exist on the host, whether a
virtualenv is active, and whether the git tree is dirty.

## Verify integrity (now or years later)

```bash
scripts/freeze/verify_freeze.sh --snapshot=<timestamp>
```

Every layer and the top level carry a `MANIFEST.sha256`.

## Restore offline (future host)

```bash
# A1 python
python/install_python_offline.sh ./arc-venv
# A1 system (root; disposable/intended host only)
sudo system/install_system_offline.sh
# A1 source
source/restore_source_offline.sh ./restored
# A2 container
container/load_container_offline.sh
# A3 image
see image/FULL_IMAGE_GUIDANCE.md
```

## Honest limitations

- **Wheels and `.deb`s are platform/ABI/release specific.** A1 reinstalls cleanly on a host
  matching the freeze platform (recorded in `python/platform.json` and
  `system/installed_versions.txt`). It is not architecture-portable.
- **The container (A2) does not contain a kernel or GPU driver.** The future host still needs
  a compatible kernel and `--device /dev/dri` passthrough.
- **Kernel `.deb`s (A1 `--include-kernel`) are cached for reference and are not guaranteed to
  install on a future OS.** For true kernel-level reproduction use A3.
- **Full images (A3) are tied to the hardware/VM topology they were captured on.** Restoring
  onto materially different hardware may not boot or may not see the A770.
- Freezing changes nothing on your system except writing the snapshot; the offline *installers*
  do modify a target host and are meant for a disposable/intended test machine.
