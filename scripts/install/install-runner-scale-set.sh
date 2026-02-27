#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd helm
require_cmd oc

require_env ARC_SYSTEM_NAMESPACE
require_env RUNNER_NAMESPACE
require_env RUNNER_SCALE_SET_NAME
require_env GITHUB_CONFIG_URL
require_env REGISTRY_HOST
require_env REGISTRY_NAMESPACE
require_env IMAGE_TAG

# Determine runner mode: "kubernetes" (default) or "dind"
RUNNER_MODE="${RUNNER_MODE:-kubernetes}"

print_header "Install ARC runner scale set (mode: ${RUNNER_MODE})"

oc create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

if [[ "${RUNNER_MODE}" == "dind" ]]; then
  require_env RUNNER_DIND_IMAGE_NAME
  RUNNER_IMAGE_FULL="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${RUNNER_DIND_IMAGE_NAME}:${IMAGE_TAG}"
  VALUES_FILE="${REPO_ROOT}/helm/runner-values-dind.yaml"
  echo "Using DinD image: ${RUNNER_IMAGE_FULL}"
  echo "DinD values file: ${VALUES_FILE}"
else
  require_env RUNNER_IMAGE_NAME
  RUNNER_IMAGE_FULL="${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${RUNNER_IMAGE_NAME}:${IMAGE_TAG}"
  VALUES_FILE="${REPO_ROOT}/helm/runner-values.yaml"
fi

helm upgrade --install "${RUNNER_SCALE_SET_NAME}" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace "${RUNNER_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
  --set githubConfigSecret="arc-ghes-github-app" \
  --set "template.spec.containers[0].image=${RUNNER_IMAGE_FULL}" \
  --set controllerServiceAccount.namespace="${ARC_SYSTEM_NAMESPACE}" \
  --set controllerServiceAccount.name="arc-gha-rs-controller"

echo "Runner scale set installed: ${RUNNER_SCALE_SET_NAME} in namespace ${RUNNER_NAMESPACE}"
echo "Mode: ${RUNNER_MODE} | Image: ${RUNNER_IMAGE_FULL}"
