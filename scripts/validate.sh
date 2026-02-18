#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_env

PASS=0
FAIL=0
WARN=0

check_pass() { echo "  [PASS] $1"; ((PASS++)); }
check_fail() { echo "  [FAIL] $1"; ((FAIL++)); }
check_warn() { echo "  [WARN] $1"; ((WARN++)); }

# ─── Preflight checks ───────────────────────────────────────────────
print_header "Preflight: required tools"

for cmd in docker oc helm git curl; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    check_pass "${cmd} found ($(command -v "${cmd}"))"
  else
    check_fail "${cmd} not found"
  fi
done

if docker buildx version >/dev/null 2>&1; then
  check_pass "docker buildx available"
else
  check_fail "docker buildx not available (required for cross-platform builds)"
fi

# ─── Environment variable checks ────────────────────────────────────
print_header "Environment: required variables"

for var in REGISTRY_HOST REGISTRY_NAMESPACE IMAGE_TAG ARC_GIT_REF \
           ARC_CONTROLLER_IMAGE_NAME RUNNER_IMAGE_NAME RUNNER_VERSION \
           RUNNER_DOWNLOAD_URL ARC_SYSTEM_NAMESPACE RUNNER_NAMESPACE \
           RUNNER_SCALE_SET_NAME GITHUB_CONFIG_URL; do
  val="${!var:-}"
  if [[ -n "${val}" ]]; then
    # mask secrets
    check_pass "${var} is set"
  else
    check_fail "${var} is empty or unset"
  fi
done

# Optional auth vars
print_header "Environment: GitHub App auth"
for var in GITHUB_APP_ID GITHUB_APP_INSTALLATION_ID GITHUB_APP_PRIVATE_KEY_PATH; do
  val="${!var:-}"
  if [[ -n "${val}" ]]; then
    check_pass "${var} is set"
  else
    check_warn "${var} is empty (required for install-github-app-secret.sh)"
  fi
done

if [[ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" && -f "${GITHUB_APP_PRIVATE_KEY_PATH}" ]]; then
  check_pass "Private key file exists at ${GITHUB_APP_PRIVATE_KEY_PATH}"
elif [[ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
  check_warn "Private key file not found: ${GITHUB_APP_PRIVATE_KEY_PATH}"
fi

# ─── Runner artifact reachability ────────────────────────────────────
print_header "Runner artifact: reachability"

if curl -fsSL --head "${RUNNER_DOWNLOAD_URL}" >/dev/null 2>&1; then
  check_pass "Runner tarball URL is reachable"
else
  check_fail "Runner tarball URL is NOT reachable: ${RUNNER_DOWNLOAD_URL}"
fi

# ─── Registry connectivity ──────────────────────────────────────────
print_header "Registry: connectivity"

if curl -fsSL --head "https://${REGISTRY_HOST}/v2/" >/dev/null 2>&1; then
  check_pass "Registry API reachable at https://${REGISTRY_HOST}/v2/"
else
  check_warn "Registry API not reachable at https://${REGISTRY_HOST}/v2/ (may need auth or is not configured yet)"
fi

# ─── Image existence checks ─────────────────────────────────────────
print_header "Registry: image existence (skipped if registry unreachable)"

for img_name in "${ARC_CONTROLLER_IMAGE_NAME}" "${RUNNER_IMAGE_NAME}"; do
  ref="$(image_ref "${img_name}")"
  if docker manifest inspect "${ref}" >/dev/null 2>&1; then
    check_pass "Image exists: ${ref}"
  else
    check_warn "Image not found: ${ref} (build and push first)"
  fi
done

# ─── OpenShift cluster checks ───────────────────────────────────────
print_header "OpenShift: cluster access"

if oc whoami >/dev/null 2>&1; then
  check_pass "Logged in to OpenShift as $(oc whoami)"
  CLUSTER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
  echo "         Cluster: ${CLUSTER}"
else
  check_warn "Not logged in to OpenShift (run 'oc login' before install scripts)"
fi

# ─── Namespace and deployment checks ────────────────────────────────
if oc whoami >/dev/null 2>&1; then
  print_header "OpenShift: namespaces"

  for ns in "${ARC_SYSTEM_NAMESPACE}" "${RUNNER_NAMESPACE}"; do
    if oc get namespace "${ns}" >/dev/null 2>&1; then
      check_pass "Namespace exists: ${ns}"
    else
      check_warn "Namespace missing: ${ns} (will be created by install scripts)"
    fi
  done

  print_header "OpenShift: ARC controller deployment"

  if oc -n "${ARC_SYSTEM_NAMESPACE}" get deployment -l app.kubernetes.io/name=gha-runner-scale-set-controller -o name 2>/dev/null | grep -q deployment; then
    check_pass "ARC controller deployment found"
    READY=$(oc -n "${ARC_SYSTEM_NAMESPACE}" get deployment -l app.kubernetes.io/name=gha-runner-scale-set-controller -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "${READY}" -ge 1 ]]; then
      check_pass "Controller has ${READY} ready replica(s)"
    else
      check_fail "Controller has 0 ready replicas"
    fi
  else
    check_warn "ARC controller deployment not found (run install-controller.sh)"
  fi

  print_header "OpenShift: GitHub App secret"

  if oc -n "${RUNNER_NAMESPACE}" get secret arc-ghes-github-app >/dev/null 2>&1; then
    check_pass "Secret arc-ghes-github-app exists in ${RUNNER_NAMESPACE}"
  else
    check_warn "Secret arc-ghes-github-app not found (run install-github-app-secret.sh)"
  fi

  print_header "OpenShift: runner scale set"

  if oc -n "${RUNNER_NAMESPACE}" get autoscalingrunnersets.actions.github.com >/dev/null 2>&1; then
    COUNT=$(oc -n "${RUNNER_NAMESPACE}" get autoscalingrunnersets.actions.github.com --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${COUNT}" -ge 1 ]]; then
      check_pass "Found ${COUNT} AutoScalingRunnerSet(s) in ${RUNNER_NAMESPACE}"
    else
      check_warn "No AutoScalingRunnerSets found (run install-runner-scale-set.sh)"
    fi
  else
    check_warn "AutoScalingRunnerSet CRD not found (install controller first)"
  fi
fi

# ─── Summary ────────────────────────────────────────────────────────
print_header "Summary"
echo "  Passed : ${PASS}"
echo "  Failed : ${FAIL}"
echo "  Warnings: ${WARN}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
  echo "Some checks FAILED. Review output above before proceeding."
  exit 1
fi

echo "All critical checks passed."
