# Research Summary: ARC on OpenShift s390x

## Scope
This summary captures findings from GitHub ARC documentation, ARC chart defaults, release metadata, and container manifest verification.

## Key findings

1. Official `actions/runner` release assets do not consistently provide `linux/s390x` in latest upstream release metadata.
2. Registry manifest checks for tested ARC controller and runner images show `amd64/arm64` primary runtime platforms.
3. ARC supports private registry image overrides through Helm values for controller and runner pod template.
4. GHES with self-hosted runners is supported, and offline/restricted environments require explicit tool-cache management.

## Implication for s390x

A production-capable `s390x` deployment requires custom image builds and pinned binary source strategy for runner payloads.

## Image matrix (implementation target)

- Controller image: custom build for `linux/s390x`.
- Runner image: custom build for `linux/s390x` using configurable runner tarball source.
- DIND runner image: optional custom build (only if SCC policy allows privileged workloads).

## Authentication design

Use GHES GitHub App credentials injected as Kubernetes secret keys:
- `github_app_id`
- `github_app_installation_id`
- `github_app_private_key`

## Operational recommendations

1. Maintain internal mirror for runner artifact tarballs.
2. Pin image tags and checksum-validate all downloaded artifacts.
3. Validate container mode and SCC constraints before enabling DIND.
4. Pre-populate runner tool cache for disconnected environments.

## Limitations

- `s390x` support relies on custom builds and environment validation.
- Upstream changes may require periodic update of image build scripts and values.
