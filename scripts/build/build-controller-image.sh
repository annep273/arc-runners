#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd docker
require_cmd git

require_env REGISTRY_HOST
require_env REGISTRY_NAMESPACE
require_env IMAGE_TAG
require_env ARC_GIT_REF
require_env ARC_CONTROLLER_IMAGE_NAME

print_header "Build ARC controller image for linux/s390x"

IMAGE="$(image_ref "${ARC_CONTROLLER_IMAGE_NAME}")"

# Clone into a system temp directory — not inside the project tree
SRC_DIR="$(mktemp -d -t arc-controller-XXXXXX)"
trap 'rm -rf "${SRC_DIR}"' EXIT

echo "Cloning actions-runner-controller at ref: ${ARC_GIT_REF}"
git clone --depth=1 --branch "${ARC_GIT_REF}" https://github.com/actions/actions-runner-controller.git "${SRC_DIR}"

echo "Building and pushing ${IMAGE}"
docker buildx build \
  --platform linux/s390x \
  --file "${SRC_DIR}/Dockerfile" \
  --tag "${IMAGE}" \
  --push \
  "${SRC_DIR}"

echo "Done: ${IMAGE}"
