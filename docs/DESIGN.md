# Design Document

## 1. Architecture summary

Deployment consists of:
- ARC controller (`gha-runner-scale-set-controller`) in `arc-systems` namespace.
- One or more runner scale sets in `arc-runners` namespace.
- Private registry-hosted images built for `linux/s390x`.
- GHES GitHub App auth secret in runner namespace.

## 2. Image strategy

### 2.1 Controller image
- Build custom `linux/s390x` image from `actions/actions-runner-controller` source Dockerfile.
- Push to `${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${ARC_CONTROLLER_IMAGE_NAME}:${IMAGE_TAG}`.

### 2.2 Runner image
- Build custom runner image for `linux/s390x`.
- Download runner tarball from configurable URL (`RUNNER_DOWNLOAD_URL`) and optionally verify SHA-256.
- Push to `${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${RUNNER_IMAGE_NAME}:${IMAGE_TAG}`.

### 2.3 DIND runner image (optional)
- Build DIND variant for OpenShift environments where privileged pods are allowed.
- Push to `${REGISTRY_HOST}/${REGISTRY_NAMESPACE}/${RUNNER_DIND_IMAGE_NAME}:${IMAGE_TAG}`.

## 3. Configuration model

### 3.1 Environment variables
Primary configuration is centralized in `.env`.

### 3.2 Helm values templates
- `helm/controller-values.yaml` controls ARC controller image repository/tag.
- `helm/runner-values.yaml` controls runner scale set config and runner pod template image.

### 3.3 GHES GitHub App secret format
Secret keys expected by ARC:
- `github_app_id`
- `github_app_installation_id`
- `github_app_private_key`

## 4. Installation flow

1. Create/refresh GitHub App secret in runner namespace.
2. Install ARC controller chart with custom controller image.
3. Install runner scale set chart with custom runner image and GHES config URL.

## 5. OpenShift considerations

- Use namespace-scoped image pull secrets for private registry access.
- Ensure trusted CA if GHES/registry uses private PKI.
- Prefer `kubernetes` container mode in restricted environments.
- DIND mode requires additional SCC privileges.

## 6. Security and compliance

- Pin image tags and runner tarball URLs.
- Optionally verify runner tarball SHA-256.
- Keep private key in file with restricted permissions, then load via script.

## 7. Validation

- Verify image manifests include `linux/s390x`.
- Confirm ARC controller deployment is healthy.
- Confirm runner scale set listener and ephemeral runners register to GHES.
- Run a sample workflow targeting runner labels.

## 8. Rollback

- Helm rollback for controller and runner releases.
- Keep previous image tags in registry for quick reversion.

## 9. Future enhancements

- Add signed image provenance (cosign) and SBOM generation.
- Add GitOps integration (Argo CD) manifests.
- Add policy checks for SCC and namespace quotas.
