#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/build-controller-image.sh"
"${SCRIPT_DIR}/build-runner-image.sh"
"${SCRIPT_DIR}/build-runner-dind-image.sh"

echo "All image builds completed."
