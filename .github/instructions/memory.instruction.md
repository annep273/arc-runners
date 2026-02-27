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

## DinD Rootless Fixes (Phase 3 — runtime errors resolved)

### Errors fixed
1. **`XDG_RUNTIME_DIR is pointing to a path which is not writable`** → Set `XDG_RUNTIME_DIR=/tmp/xdg-run-1001`, created dir at build time and mounted as emptyDir at runtime.
2. **`"/" is not a shared mount`** → Set `BUILDAH_ISOLATION=chroot` which bypasses mount propagation requirements entirely.
3. **`cannot setup namespace using newuidmap` / `newuidmap: open of uid_map failed: Permission denied`** → Set `_CONTAINERS_USERNS_CONFIGURED=1` to bypass user namespace setup; falls back to single-UID mapping.
4. **`Failed to decode the keys ["network.network_backend"]`** → Created clean `containers.conf` without that key; only safe defaults.
5. **`mkdir /run/containers: permission denied`** → Changed `runroot` from `/run/user/1001` to `/tmp/containers-run-1001`.
6. **chown errors in single-UID mapping** → Added `ignore_chown_errors = "true"` in `storage.conf` for both vfs and overlay.

### Root pattern: VFS + chroot isolation
- `STORAGE_DRIVER=vfs` — no kernel module deps, works with single-UID mapping, no fuse-overlayfs needed.
- `BUILDAH_ISOLATION=chroot` — avoids runc/crun user namespace requirements (no unshare call).
- `_CONTAINERS_USERNS_CONFIGURED=1` — tells containers libraries to skip newuidmap/newgidmap.
- `ignore_chown_errors=true` — handles single-UID mapping where chown operations would fail.
- Trade-off: VFS is slower than overlay (full copy vs reflink/copy-on-write), but universally compatible with unprivileged pods.

### Three security tracks in `helm/runner-values-dind.yaml`
- **Track A (strict non-root, default):** `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, drop ALL caps. Most restrictive. Works with VFS+chroot.
- **Track B (hostUsers: false):** Requires Kubernetes 1.30+ with `UserNamespacesSupport` feature gate. Kernel maps UID range into pod; allows overlay storage and fuse-overlayfs.
- **Track C (SETUID/SETGID caps):** For OpenShift `anyuid` SCC. Adds SETUID+SETGID caps + `allowPrivilegeEscalation: true`. Enables newuidmap/newgidmap for full user namespace support.

### Files changed in Phase 3
- `docker/runner-s390x-dind/Dockerfile` — complete rewrite with VFS+chroot config.
- `helm/runner-values-dind.yaml` — NEW: dedicated DinD Helm values with Track A/B/C options.
- `scripts/install/install-runner-scale-set.sh` — added `RUNNER_MODE` (dind|kubernetes) support.
- `.env.example` — added `RUNNER_MODE=kubernetes`.
- `scripts/test-dind-rootless.sh` — NEW: smoke test script.
- `docs/test-dind-pod.yaml` — NEW: test pod manifest for cluster validation.

### Images pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.1-s390x` — verified via registry API (User=1001, all 4 ENV vars confirmed, architecture=s390x).

### Research sources
- CERN blog: rootless container builds on Kubernetes (June 2025) — hostUsers: false + overlay + emptyDir pattern.
- Red Hat OpenShift Pipelines docs: unprivileged buildah — SETUID/SETGID + allowPrivilegeEscalation pattern.
- buildah GitHub issue #4049 / discussion #5720 — `cat /proc/self/uid_map` diagnosis.
- oneuptime blog: rootless buildah in Kubernetes CI — VFS + chroot + SETUID/SETGID caps pattern.
- buildah tutorial 05: OpenShift rootless with anyuid SCC.

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
- Default mode for OpenShift/s390x: `containerMode: kubernetes` (safest, no privileged pods).
- For workloads needing in-pod image builds: use DinD mode with `runner-values-dind.yaml` Track A (VFS+chroot, strict non-root).
- Track B (hostUsers: false) is preferred when on Kubernetes 1.30+ — enables overlay storage for better build performance.
- Track C (SETUID/SETGID caps) for OpenShift with `anyuid` SCC — enables newuidmap/newgidmap.
- Prefer daemonless builders (buildah/kaniko) over Docker daemon; our DIND image uses podman/buildah (no dockerd).

## Decision rule to remember
If a repository accepts untrusted PR code, route it to the most isolated ephemeral runner group with strict non-root + no privileged containers, and never share that pool with deployment-capable workloads.
