#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd oc

require_env RUNNER_NAMESPACE
require_env REGISTRY_PULL_SECRET_NAME
require_env REGISTRY_HOST
require_env REGISTRY_USERNAME
require_env REGISTRY_PASSWORD
require_env REGISTRY_EMAIL

print_header "Create/update registry pull secret"

oc create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

oc -n "${RUNNER_NAMESPACE}" delete secret "${REGISTRY_PULL_SECRET_NAME}" --ignore-not-found
oc -n "${RUNNER_NAMESPACE}" create secret docker-registry "${REGISTRY_PULL_SECRET_NAME}" \
  --docker-server="${REGISTRY_HOST}" \
  --docker-username="${REGISTRY_USERNAME}" \
  --docker-password="${REGISTRY_PASSWORD}" \
  --docker-email="${REGISTRY_EMAIL}"

echo "Created pull secret: ${RUNNER_NAMESPACE}/${REGISTRY_PULL_SECRET_NAME}"
echo "Add this secret under helm/runner-values.yaml template.spec.imagePullSecrets when needed."
