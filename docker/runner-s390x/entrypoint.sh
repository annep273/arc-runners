#!/usr/bin/env bash
set -euo pipefail

# Fallback entrypoint for the ARC runner image.
# The ARC chart normally overrides the command to /home/runner/run.sh directly.
# This script is kept as a safety net if the image is run standalone.

if [[ -n "${RUNNER_DEBUG:-}" ]]; then
  set -x
fi

cd /home/runner

if [[ ! -f ./run.sh ]]; then
  echo "ERROR: runner payload not found in $(pwd)"
  exit 1
fi

exec ./run.sh "$@"
