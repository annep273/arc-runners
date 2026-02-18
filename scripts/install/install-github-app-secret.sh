#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"

load_env
require_cmd oc

require_env RUNNER_NAMESPACE
require_env GITHUB_APP_ID
require_env GITHUB_APP_INSTALLATION_ID
require_env GITHUB_APP_PRIVATE_KEY_PATH

print_header "Create/update GitHub App secret for ARC"

if [[ ! -f "${GITHUB_APP_PRIVATE_KEY_PATH}" ]]; then
  echo "ERROR: private key file not found: ${GITHUB_APP_PRIVATE_KEY_PATH}"
  exit 1
fi

oc create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

oc -n "${RUNNER_NAMESPACE}" delete secret arc-ghes-github-app --ignore-not-found
oc -n "${RUNNER_NAMESPACE}" create secret generic arc-ghes-github-app \
  --from-literal=github_app_id="${GITHUB_APP_ID}" \
  --from-literal=github_app_installation_id="${GITHUB_APP_INSTALLATION_ID}" \
  --from-file=github_app_private_key="${GITHUB_APP_PRIVATE_KEY_PATH}"

echo "Secret created: ${RUNNER_NAMESPACE}/arc-ghes-github-app"
