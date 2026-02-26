#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd docker

require_env REGISTRY_HOST
require_env REGISTRY_NAMESPACE
require_env IMAGE_TAG
require_env RUNNER_IMAGE_NAME
require_env RUNNER_VERSION
require_env RUNNER_DOWNLOAD_URL

print_header "Build ARC runner image for linux/s390x"

IMAGE="$(image_ref "${RUNNER_IMAGE_NAME}")"
DOCKER_CONTEXT="${REPO_ROOT}/docker/runner-s390x"

echo "Building and pushing ${IMAGE}"
docker buildx build \
  --platform linux/s390x \
  --build-arg RUNNER_VERSION="${RUNNER_VERSION}" \
  --build-arg RUNNER_DOWNLOAD_URL="${RUNNER_DOWNLOAD_URL}" \
  --build-arg RUNNER_DOWNLOAD_SHA256="${RUNNER_DOWNLOAD_SHA256:-}" \
  --build-arg RUNNER_CONTAINER_HOOKS_VERSION="${RUNNER_CONTAINER_HOOKS_VERSION:-}" \
  --file "${DOCKER_CONTEXT}/Dockerfile" \
  --tag "${IMAGE}" \
  --push \
  "${DOCKER_CONTEXT}"

echo "Done: ${IMAGE}"
