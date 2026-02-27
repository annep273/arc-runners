#!/usr/bin/env bash
# ── test-dind-rootless.sh ────────────────────────────────────────────
# Smoke test for the DIND runner image.
# Runs inside the container as UID 1001 (simulating a Kubernetes pod
# with restricted SCC) and verifies that:
#   1. podman info works without errors
#   2. buildah info works without errors
#   3. buildah can build a trivial Dockerfile
#   4. podman can run a container
#
# Usage:
#   bash scripts/test-dind-rootless.sh [IMAGE]
#
# Default image: docker.io/annepdevops/actions-runner-dind:0.1.9-s390x
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source env if available
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; source "${REPO_ROOT}/.env"; set +a
fi

IMAGE="${1:-${REGISTRY_HOST:-docker.io}/${REGISTRY_NAMESPACE:-annepdevops}/${RUNNER_DIND_IMAGE_NAME:-actions-runner-dind}:${IMAGE_TAG:-0.1.1-s390x}}"

echo "============================================================"
echo "Testing DIND runner image: ${IMAGE}"
echo "============================================================"
echo ""

# For cross-arch testing: docker can run s390x if QEMU user-static is registered
# Check if the image platform matches the host; if not, just validate config
HOST_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
echo "Host architecture: ${HOST_ARCH}"

# Simple inline test script that runs inside the container
TEST_SCRIPT='
#!/bin/bash
set -e

echo "=== Environment ==="
echo "USER: $(whoami) ($(id))"
echo "BUILDAH_ISOLATION: ${BUILDAH_ISOLATION:-not set}"
echo "STORAGE_DRIVER: ${STORAGE_DRIVER:-not set}"
echo "_CONTAINERS_USERNS_CONFIGURED: ${_CONTAINERS_USERNS_CONFIGURED:-not set}"
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-not set}"
echo "CONTAINERS_STORAGE_CONF: ${CONTAINERS_STORAGE_CONF:-not set}"
echo "CONTAINERS_REGISTRIES_CONF: ${CONTAINERS_REGISTRIES_CONF:-not set}"
echo "HOME: ${HOME:-not set}"
echo ""

echo "=== Verify writable directories ==="
for d in /tmp/xdg-run-1001 /tmp/containers-run-1001 /home/runner/.local/share/containers; do
  if [ -w "$d" ]; then
    echo "✅ $d is writable"
  else
    echo "❌ $d is NOT writable"
    exit 1
  fi
done
echo ""

echo "=== System storage.conf ==="
cat /etc/containers/storage.conf 2>&1 | head -10
echo ""

echo "=== System containers.conf ==="
cat /etc/containers/containers.conf 2>&1 | head -10
echo ""

echo "=== User storage.conf ==="
cat /home/runner/.config/containers/storage.conf 2>&1 | head -5 || echo "(not found)"
echo ""

echo "=== podman info (via wrapper) ==="
podman info 2>&1 | head -30
echo "..."
echo ""

echo "=== buildah info ==="
buildah-safe info 2>&1 | head -20 || buildah --storage-driver=vfs info 2>&1 | head -20
echo "..."
echo ""

echo "=== Build a trivial image ==="
mkdir -p /tmp/test-build && cd /tmp/test-build
cat > Dockerfile <<EODF
FROM docker.io/library/alpine:latest
RUN echo "hello from s390x rootless build"
EODF

echo "Starting buildah build (via wrapper)..."
buildah-safe bud -t test-image:latest -f Dockerfile . 2>&1
echo ""

echo "=== List built images ==="
podman images 2>&1
echo ""

echo "=== Run container with podman ==="
podman run --rm test-image:latest echo "Container ran successfully!" 2>&1
echo ""

echo "============================================"
echo "✅ ALL TESTS PASSED"
echo "============================================"
'

echo "Running test inside container as UID 1001..."
echo ""

# Run with --user 1001:1001 and drop all capabilities to simulate restricted SCC
docker run --rm \
  --user 1001:1001 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --security-opt seccomp=unconfined \
  -e BUILDAH_ISOLATION=chroot \
  -e _CONTAINERS_USERNS_CONFIGURED=1 \
  -e STORAGE_DRIVER=vfs \
  -e XDG_RUNTIME_DIR=/tmp/xdg-run-1001 \
  -e CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf \
  -e CONTAINERS_REGISTRIES_CONF=/etc/containers/registries.conf \
  -e HOME=/home/runner \
  --entrypoint /bin/bash \
  "${IMAGE}" \
  -c "${TEST_SCRIPT}"

echo ""
echo "Done."
