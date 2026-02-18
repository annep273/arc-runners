#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env() {
  local env_file="${REPO_ROOT}/.env"
  if [[ ! -f "${env_file}" ]]; then
    echo "ERROR: missing ${env_file}. Create it from template values first."
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${cmd}"
    exit 1
  fi
}

require_env() {
  local key="$1"
  local value="${!key:-}"
  if [[ -z "${value}" ]]; then
    echo "ERROR: required environment variable is empty: ${key}"
    exit 1
  fi
}

image_ref() {
  local image_name="$1"
  echo "${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${image_name}:${IMAGE_TAG}"
}

print_header() {
  local message="$1"
  echo ""
  echo "============================================================"
  echo "${message}"
  echo "============================================================"
}
