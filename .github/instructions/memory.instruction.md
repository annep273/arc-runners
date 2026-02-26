---
applyTo: '**'
---

# ARC Runners Memory: Non-Root Mode + GitHub Workload Practices (2026-02-25)

## Authoritative references checked
- GitHub Docs: Deploying runner scale sets with ARC (container modes, dind rootless example, security warnings).
- GitHub Docs: Actions Runner Controller concepts (runner image requirements, lifecycle, hooks).
- GitHub Docs: Self-hosted runners reference (ephemeral recommendation, update policy, networking).
- GitHub Docs: Secure use reference (hardening for self-hosted and GitHub-hosted runners).
- GitHub Docs: GitHub-hosted runners (ephemeral VM model, image update cadence, hosts controls).
- ARC chart values.yaml from official repo (default dind uses privileged docker:dind; customization required for rootless patterns).
- Docker docs: rootless mode prerequisites and limitations caveat (as linked by GitHub ARC docs).

## What GitHub follows for workload execution (baseline)
1. GitHub-hosted runners are mostly fresh VMs per job (except single-CPU class), emphasizing clean ephemeral isolation.
2. GitHub recommends ephemeral/JIT self-hosted runners for autoscaling and reduced persistence risk.
3. GitHub recommends separating runner namespaces from controller namespace and isolating production workloads.
4. GitHub warns that self-hosted runners can be persistently compromised if reused; avoid broad trust boundaries.
5. ARC defaults for `dind` use privileged containers; safer alternatives require explicit customization.
6. In Kubernetes mode, container hooks run container jobs in separate pods; requiring job containers is the safer default.
7. GitHub recommends secrets via Kubernetes secrets / GitHub App auth and least-privilege token scopes.

## Non-root mode findings specific to ARC
1. Runner container non-root operation is standard (`runner` UID/GID pattern around 1001).
2. `containerMode: kubernetes` is the preferred non-privileged pattern for Kubernetes clusters.
3. `containerMode: dind` requires privileged daemon container by default.
4. `dind-rootless` is possible, but still requires privileged pod context in ARC examples and has Docker rootless limitations.
5. `kubernetes-novolume` mode requires root for lifecycle hook operations; not suitable for strict non-root posture.

## Current repo status (implementation completed)
1. `helm/runner-values.yaml` uses `containerMode: kubernetes` with full pod + container securityContext (runAsNonRoot, UID 1001, drop ALL caps, seccomp RuntimeDefault).
2. `helm/controller-values.yaml` has pod + container securityContext (runAsNonRoot, UID 1000, readOnlyRootFilesystem, drop ALL caps).
3. `docker/runner-s390x/Dockerfile` runs as UID 1001, NO `RUNNER_ALLOW_RUNASROOT`. Matches official image patterns: docker group GID 123, sudo group, OCI labels, conditional runner-container-hooks install.
4. `docker/runner-s390x-dind/Dockerfile` uses `apt-get` (Ubuntu base), installs podman/buildah/skopeo/fuse-overlayfs/slirp4netns, rootless podman config, subuid/subgid, runs as UID 1001.
5. `scripts/build/build-runner-image.sh` passes `RUNNER_CONTAINER_HOOKS_VERSION` build-arg.
6. `.env.example` includes `RUNNER_CONTAINER_HOOKS_VERSION` variable.
7. `docker/runner-s390x/entrypoint.sh` is minimal and secure (set -euo pipefail, no root assumptions).

## Enhancements implemented (P0 complete)
- [x] Removed `RUNNER_ALLOW_RUNASROOT=1` from base runner image
- [x] Added `RUNNER_MANUALLY_TRAP_SIG=1` and `ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1`
- [x] Added `ImageOS=ubuntu22` env var
- [x] Added docker group (GID 123) + sudo group with NOPASSWD
- [x] Added OCI labels to both images
- [x] Added conditional runner-container-hooks installation
- [x] Fixed DIND Dockerfile: microdnf → apt-get
- [x] Added slirp4netns for rootless networking in DIND
- [x] Added subuid/subgid for rootless podman
- [x] Added podman registries.conf
- [x] Enforced securityContext in runner-values.yaml (pod + container level)
- [x] Enforced securityContext in controller-values.yaml (pod + container level)
- [x] Added listener pod securityContext in runner-values.yaml
- [x] Added RUNNER_CONTAINER_HOOKS_VERSION to build script and .env.example

## Enhancements remaining (P1-P3)
### P1 (image reliability and supply chain)
1. Fix `runner-s390x-dind` package installation path (Ubuntu apt packages vs UBI/microdnf) and align base/runtime assumptions.
2. Pin all downloaded artifacts by immutable version + SHA256 (runner tarball, hooks, any docker/buildx/static binaries).
3. Add SBOM generation and image signing/provenance (cosign + attestations) in build pipeline.
4. Add periodic CVE scanning gate on built images (e.g., Trivy/Grype) with fail thresholds.

### P2 (operational hardening)
1. Forward ephemeral runner logs externally by default (required for troubleshooting in ephemeral model).
2. Configure network policy egress allowlist for required GitHub domains only.
3. Define dedicated ServiceAccounts and minimal RBAC for runner pods and hook-created job pods.
4. Add PodDisruptionBudget / anti-affinity / per-namespace quotas for production isolation.

### P3 (workflow-level security hygiene)
1. Require pinned actions by full commit SHA in org/repo policy.
2. Default `GITHUB_TOKEN` permissions to read-only; elevate per-job.
3. Prefer OIDC short-lived credentials instead of long-lived cloud secrets.
4. Enable Dependabot updates for workflow actions and dependency review on PRs.

## Practical mode guidance for this project
- Default mode for OpenShift/s390x: `containerMode: kubernetes`.
- Only enable `dind`/`dind-rootless` for workloads that truly need Docker daemon semantics and can tolerate privileged SCC.
- Prefer daemonless builders (buildah/kaniko/buildkit rootless patterns) where possible to avoid privileged pods.

## Decision rule to remember
If a repository accepts untrusted PR code, route it to the most isolated ephemeral runner group with strict non-root + no privileged containers, and never share that pool with deployment-capable workloads.
