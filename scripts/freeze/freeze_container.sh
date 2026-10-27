#!/usr/bin/env bash
# freeze_container.sh — A2: save a container image of the user-space stack to a tarball.
# Builds (or tags) an image, then `docker save`/`podman save` it into the snapshot so it
# can be `load`ed offline later. Does NOT include the host kernel/i915 driver — the future
# host still needs a compatible kernel + /dev/dri passthrough (documented in the README).
#
# Usage:
#   scripts/freeze/freeze_container.sh --i-say-so --note="..." [--snapshot=DIR] \
#       [--image=NAME:TAG] [--dockerfile=PATH]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SNAPSHOT=""; IMAGE=""; DOCKERFILE=""
for arg in "$@"; do case "$arg" in
  --snapshot=*)   SNAPSHOT="${arg#--snapshot=}";;
  --image=*)      IMAGE="${arg#--image=}";;
  --dockerfile=*) DOCKERFILE="${arg#--dockerfile=}";;
esac; done
freeze_parse_dry_run "$@"
NOTE="$(require_good_run_confirmation "$@")"
[ -n "${SNAPSHOT}" ] || SNAPSHOT="${FREEZE_ROOT_DEFAULT}/$(freeze_timestamp)"
OUT="${SNAPSHOT}/container"
mkdir_unless_dry "${OUT}"

# Pick an engine.
ENGINE=""
if have docker; then ENGINE="docker"; elif have podman; then ENGINE="podman"; else
  die "neither docker nor podman found; cannot build the A2 container image"
fi
log "using container engine: ${ENGINE} (note: ${NOTE})"

[ -n "${IMAGE}" ] || IMAGE="arc-a770-lab:$(freeze_timestamp)"
[ -n "${DOCKERFILE}" ] || DOCKERFILE="${REPO_ROOT}/scripts/freeze/Dockerfile.frozen"
[ -f "${DOCKERFILE}" ] || die "dockerfile not found: ${DOCKERFILE}"

# Build the image from the frozen Dockerfile.
log "building ${IMAGE} from ${DOCKERFILE}"
if is_dry_run; then
  dry_note "build image ${IMAGE} from ${DOCKERFILE} (context: ${REPO_ROOT})"
  dry_note "  \$ ${ENGINE} build -f ${DOCKERFILE} -t ${IMAGE} ${REPO_ROOT}"
  dry_note "save image -> ${OUT}/image.tar"
  dry_note "  \$ ${ENGINE} save ${IMAGE} -o ${OUT}/image.tar"
  dry_note "generate load_container_offline.sh"
  log "DRY RUN complete: previewed container freeze (no build/save)."
  echo "${SNAPSHOT}"
  exit 0
fi
"${ENGINE}" build -f "${DOCKERFILE}" -t "${IMAGE}" "${REPO_ROOT}" \
  2>&1 | tee "${OUT}/build.log"

# Save to a portable tarball.
TARBALL="${OUT}/image.tar"
log "saving image -> ${TARBALL}"
"${ENGINE}" save "${IMAGE}" -o "${TARBALL}"
echo "${IMAGE}" > "${OUT}/image_ref.txt"

# Offline load helper.
cat > "${OUT}/load_container_offline.sh" <<'LOAD'
#!/usr/bin/env bash
# Load the frozen container image offline.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(command -v docker || command -v podman)"
[ -n "${ENGINE}" ] || { echo "no docker/podman"; exit 1; }
"${ENGINE}" load -i "${HERE}/image.tar"
echo "Loaded image: $(cat "${HERE}/image_ref.txt")"
echo "Run with GPU passthrough, e.g.:"
echo "  ${ENGINE} run --rm --device /dev/dri -it $(cat "${HERE}/image_ref.txt") bash"
LOAD
chmod +x "${OUT}/load_container_offline.sh"

write_sha256_manifest "${OUT}"
log "container freeze complete: ${OUT}"
echo "${SNAPSHOT}"
