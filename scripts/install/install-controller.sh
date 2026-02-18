#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd helm
require_cmd oc

require_env ARC_SYSTEM_NAMESPACE
require_env REGISTRY_HOST
require_env REGISTRY_NAMESPACE
require_env ARC_CONTROLLER_IMAGE_NAME
require_env IMAGE_TAG

print_header "Install ARC controller"

oc create namespace "${ARC_SYSTEM_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

CONTROLLER_IMAGE_REPO="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${ARC_CONTROLLER_IMAGE_NAME}"

# Install using the same chart version as the controller image we built
helm upgrade --install arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version "${ARC_CONTROLLER_VERSION:-0.13.1}" \
  --namespace "${ARC_SYSTEM_NAMESPACE}" \
  --values "${REPO_ROOT}/helm/controller-values.yaml" \
  --set image.repository="${CONTROLLER_IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}"

echo "ARC controller installed in namespace: ${ARC_SYSTEM_NAMESPACE}"
echo "Verify: oc -n ${ARC_SYSTEM_NAMESPACE} get pods"
