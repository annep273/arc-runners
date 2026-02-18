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
require_env RUNNER_DIND_IMAGE_NAME
require_env RUNNER_IMAGE_NAME

print_header "Build ARC runner dind image for linux/s390x"

DIND_IMAGE="$(image_ref "${RUNNER_DIND_IMAGE_NAME}")"
BASE_RUNNER_IMAGE="$(image_ref "${RUNNER_IMAGE_NAME}")"
DIND_CONTEXT="${REPO_ROOT}/docker/runner-s390x-dind"

echo "Base runner image : ${BASE_RUNNER_IMAGE}"
echo "DIND image target  : ${DIND_IMAGE}"

echo "Building and pushing ${DIND_IMAGE}"
docker buildx build \
  --platform linux/s390x \
  --build-arg BASE_IMAGE="${BASE_RUNNER_IMAGE}" \
  --file "${DIND_CONTEXT}/Dockerfile" \
  --tag "${DIND_IMAGE}" \
  --push \
  "${DIND_CONTEXT}"

echo "Done: ${DIND_IMAGE}"
