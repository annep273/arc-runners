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

## DinD Rootless Fixes (Phase 3 — v0.1.1, initial attempt)

### Errors targeted (v0.1.1)
1. `XDG_RUNTIME_DIR is pointing to a path which is not writable`
2. `"/" is not a shared mount`
3. `cannot setup namespace using newuidmap` / `newuidmap: open of uid_map failed`
4. `Failed to decode the keys ["network.network_backend"]`
5. `mkdir /run/containers: permission denied`
6. chown errors in single-UID mapping

### v0.1.1 approach (partially effective)
- Set `XDG_RUNTIME_DIR=/tmp/xdg-run-1001`, `BUILDAH_ISOLATION=chroot`, `_CONTAINERS_USERNS_CONFIGURED=1`, `STORAGE_DRIVER=vfs`.
- Created user-level configs at `~/.config/containers/storage.conf` and `~/.config/containers/containers.conf`.
- **Result: Still failing at runtime.** User reported "still getting the same issue."

### Image pushed (v0.1.1)
- `docker.io/annepdevops/actions-runner-dind:0.1.1-s390x`

## DinD Rootless Fixes (Phase 4 — v0.1.2, definitive fix via deep research)

### Root cause analysis (DEFINITIVE — from source code review)

**Why v0.1.1 failed:** User-level configs (`~/.config/containers/`) are read AFTER system-level configs. The Ubuntu 22.04 `containers-common` package installs system-level configs at `/etc/containers/` and `/usr/share/containers/` that contain TOML keys incompatible with podman 3.4.4.

**Source code evidence (verified by reading actual Go source):**
1. **`containers/storage` v1.38.2** (`types/options.go` + `store.go`):
   - `ReloadConfigurationFile()` uses `toml.DecodeFile()` + `meta.Undecoded()` — any unrecognized TOML key triggers "Failed to decode the keys" warning
   - Config precedence: `/usr/share/containers/storage.conf` → `/etc/containers/storage.conf` → `$CONTAINERS_STORAGE_CONF` env var → `~/.config/containers/storage.conf`
   - The `STORAGE_DRIVER` env var is honored in `GetDefaultStoreOptionsForUIDAndGID()` but only AFTER config file is fully parsed (including unknown keys)
   - `CONTAINERS_STORAGE_CONF` env var forces a specific config path, bypassing discovery

2. **`containers/common` v0.44.0** (`containers.conf` template):
   - `network_backend` key does NOT exist in v0.44 (it was added in ~v0.47+)
   - Ubuntu 22.04 ships containers-common v0.44 but the package may install a `/etc/containers/containers.conf` with newer keys
   - This mismatch causes "Failed to decode the keys ['network.network_backend']" error

3. **Ubuntu 22.04 package versions confirmed:**
   - `podman` = 3.4.4+ds1-1ubuntu1.22.04.3 (very old, late 2021)
   - `buildah` = 1.23.1 (very old)
   - `containers-common` = 0.44.4+ds1-1ubuntu1 → containers/common v0.44

### 7 key fixes in v0.1.2 (vs v0.1.1)

| # | What changed | Why |
|---|---|---|
| 1 | Replace ALL system-level configs (`/etc/containers/storage.conf`, `/etc/containers/containers.conf`, `/usr/share/containers/storage.conf`, `/usr/share/containers/containers.conf`) | Previous version only added user-level configs which are parsed AFTER system configs |
| 2 | `containers.conf` uses ONLY TOML keys valid for containers-common v0.44 | NO `network_backend`, NO `[secrets]` section — eliminates "Failed to decode" errors |
| 3 | Set `userns = "host"`, `netns = "host"`, `no_pivot_root = true` in containers.conf | Prevents podman/buildah from attempting namespace/mount operations |
| 4 | Set `CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf` env var | Ultimate storage config override — bypasses all discovery logic |
| 5 | Set `CONTAINERS_REGISTRIES_CONF=/etc/containers/registries.conf` env var | Explicit registry config path |
| 6 | Created wrapper scripts (`/usr/local/bin/docker`, `podman`, `podman-safe`, `buildah-safe`) with explicit CLI flags | `--storage-driver=vfs --root=... --runroot=...` as ultimate fallback |
| 7 | Use `chown -R 1001:0` instead of `runner:docker` | `docker` group doesn't exist in base image; GID 0 (root group) always exists |

### Root pattern: VFS + chroot + system-level config replacement
- `STORAGE_DRIVER=vfs` — no kernel module deps, works with single-UID mapping, no fuse-overlayfs needed.
- `BUILDAH_ISOLATION=chroot` — avoids runc/crun user namespace requirements (no unshare call).
- `_CONTAINERS_USERNS_CONFIGURED=1` — tells containers libraries to skip newuidmap/newgidmap.
- `CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf` — forces storage config path, bypasses discovery.
- `ignore_chown_errors=true` — handles single-UID mapping where chown operations would fail.
- **CRITICAL**: Replace system-level configs, not just add user-level ones.
- Trade-off: VFS is slower than overlay (full copy vs reflink/copy-on-write), but universally compatible with unprivileged pods.

### Three security tracks in `helm/runner-values-dind.yaml`
- **Track A (strict non-root, default):** `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, drop ALL caps. Most restrictive. Works with VFS+chroot.
- **Track B (hostUsers: false):** Requires Kubernetes 1.30+ with `UserNamespacesSupport` feature gate. Kernel maps UID range into pod; allows overlay storage and fuse-overlayfs.
- **Track C (SETUID/SETGID caps):** For OpenShift `anyuid` SCC. Adds SETUID+SETGID caps + `allowPrivilegeEscalation: true`. Enables newuidmap/newgidmap for full user namespace support.

### Files changed in Phase 3+4
- `docker/runner-s390x-dind/Dockerfile` — complete rewrite with VFS+chroot config + system-level config replacement.
- `helm/runner-values-dind.yaml` — dedicated DinD Helm values with Track A/B/C options + new env vars.
- `scripts/install/install-runner-scale-set.sh` — added `RUNNER_MODE` (dind|kubernetes) support.
- `.env.example` — added `RUNNER_MODE=kubernetes`, updated `IMAGE_TAG=0.1.2-s390x`.
- `scripts/test-dind-rootless.sh` — smoke test script (updated for v0.1.2 env vars).
- `docs/test-dind-pod.yaml` — test pod manifest (updated for v0.1.2 image + env vars).

### Images pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.1-s390x` — v0.1.1, initial attempt (user-level configs only, still broken at runtime).
- `docker.io/annepdevops/actions-runner-dind:0.1.2-s390x` — v0.1.2, comprehensive fix (system-level config replacement). Digest: `sha256:551c75fc9f0d1977a68a7ea8d44b037b9f30430c275a1de1d3967425abe58035`. Verified via registry API.

### Key ENV vars in v0.1.2 Dockerfile
```
BUILDAH_ISOLATION=chroot
_CONTAINERS_USERNS_CONFIGURED=1
STORAGE_DRIVER=vfs
CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf
CONTAINERS_REGISTRIES_CONF=/etc/containers/registries.conf
XDG_RUNTIME_DIR=/tmp/xdg-run-1001
HOME=/home/runner
```

### Research sources
- **containers/storage v1.38.2 source code** (`types/options.go`, `store.go`) — config precedence and TOML decoding logic.
- **containers/common v0.44.0 source code** (`containers.conf` template) — confirmed `network_backend` absent in v0.44.
- CERN blog: rootless container builds on Kubernetes (June 2025) — hostUsers: false + overlay + emptyDir pattern.

## DinD Rootless Fixes (Phase 5 — v0.1.3, lchown/ignore_chown_errors fix)

### v0.1.2 runtime errors (reported by user)
1. `Failed to decode the keys ["network.network_backend"]` — STILL present (likely ARC or volume mount recreating user-level config)
2. `error running newuidmap/newgidmap` — WARNING only, expected with `_CONTAINERS_USERNS_CONFIGURED=1`
3. **CRITICAL**: `ApplyLayer exit status 1: potentially insufficient UIDs or GIDs available in user namespace (requested 0:42 for /etc/gshadow): lchown /etc/gshadow: invalid argument` — Fatal during layer extraction

### Root cause analysis (from containers/storage v1.38.2 source code)

**Why v0.1.2 failed:** Two issues:

1. **`ignore_chown_errors` placement**: Was under `[storage.options.overlay]` and `[storage.options.vfs]` per-driver subsections only. containers/storage v1.38.2 VFS driver `Init()` parses `DriverOptions` which come from the **global** `[storage.options]` map, NOT from per-driver TOML subsections. The VFS-specific subsection `[storage.options.vfs]` was added in newer versions. Fix: put `ignore_chown_errors = "true"` at global `[storage.options]` level.

2. **Wrapper scripts naming**: Were named `podman-safe`/`buildah-safe` at `/usr/local/bin/`. CI workflows calling `buildah bud` or `podman build` directly resolved to `/usr/bin/buildah` which lacks `--storage-opt ignore_chown_errors=true` flag.

**Source code evidence (verified by reading Go source):**
- `drivers/vfs/driver.go` `Init()`: parses `".ignore_chown_errors"` and `"vfs.ignore_chown_errors"` from `options.DriverOptions` → sets `d.ignoreChownErrors`
- `drivers/vfs/driver.go` `ApplyDiff()`: sets `options.IgnoreChownErrors = d.ignoreChownErrors` → calls `d.naiveDiff.ApplyDiff()`
- `drivers/driver.go`: `ApplyDiffOpts` struct has `IgnoreChownErrors bool` and `ForceMask *os.FileMode`
- `pkg/archive/archive.go` `createTarFile()`: calls `idtools.SafeLchown()` → if error AND `ignoreChownErrors` → prints warning but continues. Error "lchown /etc/gshadow: invalid argument" happens here when `ignoreChownErrors` is false.
- `pkg/archive/diff.go` `UnpackLayer()`: passes `IgnoreChownErrors` and `ForceMask` through to `createTarFile`
- Unix StackExchange confirmed: `ignore_chown_errors` must be at global `[storage.options]` level for v1.38.x

### 3 key fixes in v0.1.3 (vs v0.1.2)

| # | What changed | Why |
|---|---|---|
| 1 | Added `ignore_chown_errors = "true"` at **global `[storage.options]`** level | containers/storage v1.38.2 reads DriverOptions from global options map, not per-driver subsections |
| 2 | Renamed wrappers from `podman-safe`/`buildah-safe` to `podman`/`buildah`/`docker` at `/usr/local/bin/` | PATH priority over `/usr/bin/` ensures ALL direct calls get correct flags |
| 3 | Added `--storage-opt ignore_chown_errors=true` to ALL wrapper scripts | Belt-and-suspenders: CLI flag overrides config even if config parsing fails |

### Image pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.3-s390x` — v0.1.3, lchown/ignore_chown_errors fix. Digest: `sha256:53424b8cd54966916d667bfb87149daa11b0fb98d5858b90468e9b1cd8965fbf`. Verified via registry API.

## DinD Rootless Fixes (Phase 6 — v0.1.4, definitive fix via source code deep dive)

### v0.1.3 runtime errors (reported by user)
1. `vfs driver does not support ignore_chown_errors options` — **FATAL**: VFS driver rejects the option key.
2. `unknown flag: --isolation` — buildah wrapper's `--isolation=chroot` is NOT a global flag.
3. `Failed to decode the keys ["network.network_backend"]` from `~/.config/containers/containers.conf` — workflow recreates user-level config with unsupported keys.
4. Build exits with code 125.

### Root cause analysis (from deep source code reading)

**Why v0.1.3 failed — THREE confirmed root causes:**

1. **`--storage-opt ignore_chown_errors=true` missing `vfs.` prefix:**
   - VFS driver `Init()` in `drivers/vfs/driver.go` `parseOptions()` only accepts keys `.ignore_chown_errors` and `vfs.ignore_chown_errors`.
   - `--storage-opt` CLI flag passes the value directly to `DriverOptions` without any prefix transformation.
   - Result: key=`ignore_chown_errors` doesn't match → **default case returns "vfs driver does not support %s options"**
   - Fix: `--storage-opt vfs.ignore_chown_errors=true`
   - NOTE: `[storage.options] ignore_chown_errors = "true"` in TOML config IS correct — `ReloadConfigurationFile()` adds the driver prefix via `fmt.Sprintf("%s.ignore_chown_errors=%s", config.Storage.Driver, ...)` which produces `"vfs.ignore_chown_errors=true"`. The bug was ONLY in the CLI `--storage-opt` wrapper.

2. **`--isolation=chroot` is NOT a global buildah flag:**
   - Confirmed from buildah v1.23.1 `cmd/buildah/main.go`: global flags are `PersistentFlags` — includes `--root`, `--runroot`, `--storage-driver`, `--storage-opt`, but NOT `--isolation`.
   - `--isolation` is a subcommand flag for `bud`, `from`, `run`.
   - When wrapper runs `buildah --isolation=chroot version`, buildah returns "unknown flag: --isolation".
   - Fix: remove `--isolation` from wrapper, rely on `BUILDAH_ISOLATION=chroot` env var (already set).

3. **`CONTAINERS_CONF` env var not set:**
   - containers/common v0.44 `pkg/config/config.go` `systemConfigs()`: when `CONTAINERS_CONF` is set, it returns ONLY that path — skips ALL system and user configs.
   - Without it, podman reads the cascade: `/usr/share/` → `/etc/` → `~/.config/`
   - Workflow creates `~/.config/containers/containers.conf` with `network_backend` key → "Failed to decode" warning.
   - Fix: `CONTAINERS_CONF=/etc/containers/containers.conf` forces reading only our clean config.

### Additional env var: STORAGE_OPTS
- `types/options.go` `ReloadConfigurationFile()`: near the end, checks `os.LookupEnv("STORAGE_OPTS")` and REPLACES all `GraphDriverOptions`.
- Setting `STORAGE_OPTS=vfs.ignore_chown_errors=true` provides ultimate env-var-level override.
- For VFS driver, `ignore_chown_errors` is the only needed option, so replacement is safe.
- This works even if no config file is read.

### TOML config → DriverOptions pipeline (definitive mapping)
```
[storage.options] ignore_chown_errors = "true"
    → ReloadConfigurationFile(): fmt.Sprintf("%s.ignore_chown_errors=%s", driver, val)
    → "vfs.ignore_chown_errors=true" ✓

[storage.options.vfs] ignore_chown_errors = "true"
    → GetGraphDriverOptions("vfs", opts): fmt.Sprintf("%s.ignore_chown_errors=%s", driverName, opts.Vfs.IgnoreChownErrors)
    → "vfs.ignore_chown_errors=true" ✓

--storage-opt ignore_chown_errors=true (CLI)
    → goes directly to DriverOptions as "ignore_chown_errors=true"
    → VFS parseOptions: key="ignore_chown_errors" → NO MATCH → ERROR ✗

--storage-opt vfs.ignore_chown_errors=true (CLI)
    → goes directly to DriverOptions as "vfs.ignore_chown_errors=true"
    → VFS parseOptions: key="vfs.ignore_chown_errors" → MATCH ✓

STORAGE_OPTS=vfs.ignore_chown_errors=true (env var)
    → ReloadConfigurationFile() replaces GraphDriverOptions
    → "vfs.ignore_chown_errors=true" ✓
```

### 5 key fixes in v0.1.4 (vs v0.1.3)

| # | What changed | Why |
|---|---|---|
| 1 | `--storage-opt vfs.ignore_chown_errors=true` (added `vfs.` prefix) | VFS driver requires prefixed key in parseOptions() |
| 2 | Removed `--isolation=chroot` from buildah wrapper | Not a global flag in buildah 1.23.1; BUILDAH_ISOLATION env var handles this |
| 3 | Added `CONTAINERS_CONF=/etc/containers/containers.conf` env var | Prevents reading workflow-created containers.conf with unknown TOML keys |
| 4 | Added `STORAGE_OPTS=vfs.ignore_chown_errors=true` env var | Belt-and-suspenders: env-var-level override independent of config files |
| 5 | Removed forced `--root`/`--runroot` from wrappers | Prevents conflict with workflow-configured storage paths |

### Key ENV vars in v0.1.4 Dockerfile (9 total)
```
BUILDAH_ISOLATION=chroot
_CONTAINERS_USERNS_CONFIGURED=1
STORAGE_DRIVER=vfs
CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf
CONTAINERS_REGISTRIES_CONF=/etc/containers/registries.conf
CONTAINERS_CONF=/etc/containers/containers.conf          # NEW in v0.1.4
STORAGE_OPTS=vfs.ignore_chown_errors=true                # NEW in v0.1.4
XDG_RUNTIME_DIR=/tmp/xdg-run-1001
HOME=/home/runner
```

### Wrapper scripts (v0.1.4)
```sh
# /usr/local/bin/podman
#!/bin/sh
exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"

# /usr/local/bin/buildah (NO --isolation!)
#!/bin/sh
exec /usr/bin/buildah \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"

# /usr/local/bin/docker
#!/bin/sh
exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
```

### Image pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.4-s390x` — v0.1.4, definitive fix. Digest: `sha256:3ee4bfde6906194d6e26f1a5fc63a50607020f4b797b4c98400dca699a0d7298`. Verified via registry API.

## DinD Rootless Fixes (Phase 7 — v0.1.5, apt-get sandbox + network_backend symlink)

### v0.1.4 runtime errors (reported by user)
1. `E: setgroups 65534 failed - setgroups (1: Operation not permitted)` — **FATAL**: apt-get sandbox drops privileges to `_apt` user, fails.
2. `E: seteuid 100 failed - seteuid (22: Invalid argument)` — same issue, apt's HTTP method can't change UID.
3. `E: Method gave invalid 400 URI Failure message: Failed to setgroups` — HTTP fetcher dies.
4. `Failed to decode the keys ["network.network_backend"]` — STILL appearing from `~/.config/containers/containers.conf`.
5. Build exits with status 100 (apt-get failure).

### Root cause analysis

**Why v0.1.4 failed — TWO confirmed root causes:**

1. **apt-get sandbox privilege dropping (FATAL):**
   - When buildah builds Debian/Ubuntu images with chroot isolation, `RUN apt-get update` executes inside a chrooted rootfs.
   - apt-get tries to drop privileges to `_apt` user (UID 100, GID 65534/nogroup) via `setgroups()` and `seteuid()`.
   - With chroot isolation, buildah creates a user namespace + mount namespace (confirmed from `chroot/run.go`: `cmd.UnshareFlags = CLONE_NEWUTS | CLONE_NEWNS`).
   - The kernel sets `/proc/PID/setgroups` to "deny" in unprivileged user namespaces (required before writing gid_map). Once "deny" is set, `setgroups()` returns EPERM.
   - Fix: `APT::Sandbox::User "root"` tells apt-get to skip privilege dropping entirely. Since we're already unprivileged, there's nothing to drop.

2. **`network_backend` warning persists despite CONTAINERS_CONF:**
   - Despite setting `CONTAINERS_CONF=/etc/containers/containers.conf` in ENV, the warning still appears.
   - Likely cause: ARC runner or workflow step overwrites `~/.config/containers/containers.conf` at runtime with a config containing `network_backend` key.
   - In v0.1.4 we COPIED our clean config to the user path. If overwritten, the clean config is lost.
   - Fix: Use a SYMLINK (`ln -sf /etc/containers/containers.conf ~/.config/containers/containers.conf`). Reads through the symlink get our clean config. If the symlink is overwritten, wrapper scripts repair it before every invocation.

### Delivery mechanism for apt sandbox fix
- **buildah chroot/run.go `setupChrootBindMounts()`**: confirmed that ALL `spec.Mounts` entries are processed as actual `unix.Mount()` bind mounts within the mount namespace.
- **subscriptions.MountsWithUIDGID()**: reads `DefaultMountsFilePath` (default: `/usr/share/containers/mounts.conf`) and returns mount specs for each line.
- **`--default-mounts-file`**: confirmed as a PersistentFlag in buildah 1.23.1 — can be passed globally.
- Pipeline: `mounts.conf` → `subscriptions.MountsWithUIDGID()` → `spec.Mounts` → `setupChrootBindMounts()` → `unix.Mount()` bind mount of `/etc/apt/apt.conf.d/99sandbox` into build container rootfs.

### 4 key fixes in v0.1.5 (vs v0.1.4)

| # | What changed | Why |
|---|---|---|
| 1 | Created `/etc/apt/apt.conf.d/99sandbox` with `APT::Sandbox::User "root";` | Disables apt privilege dropping in all build containers |
| 2 | Created `/usr/share/containers/mounts.conf` to auto-inject `99sandbox` | buildah's subscriptions mechanism bind-mounts this into every RUN step |
| 3 | buildah wrapper adds `--default-mounts-file=/usr/share/containers/mounts.conf` | Belt-and-suspenders: explicitly points to mounts.conf |
| 4 | User containers.conf is now a SYMLINK + wrapper scripts repair it before each run | Prevents overwritten user-level config from causing decode warnings |

### Wrapper scripts (v0.1.5)
All wrappers now include symlink repair before execution:
```sh
# /usr/local/bin/podman (and /usr/local/bin/docker)
#!/bin/sh
# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi
exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"

# /usr/local/bin/buildah (adds --default-mounts-file)
#!/bin/sh
# (same symlink repair)
exec /usr/bin/buildah \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  --default-mounts-file=/usr/share/containers/mounts.conf \
  "$@"
```

### Image pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.5-s390x` — v0.1.5, apt sandbox + symlink fix. Digest: `sha256:7e637f3a961aeae906c1cee09bdaa04cc05d6b5c0957a14dbff225dde779ba04`. Verified via registry API.

### Research sources (Phase 7)
- **buildah v1.23.1 `chroot/run.go`** — confirmed `setupChrootBindMounts()` processes ALL `spec.Mounts` with `unix.Mount()`; confirmed `cmd.UnshareFlags = CLONE_NEWUTS | CLONE_NEWNS`
- **buildah v1.23.1 `run_linux.go`** — confirmed `subscriptions.MountsWithUIDGID(b.MountLabel, cdir, b.DefaultMountsFilePath, ...)` reads mounts.conf
- **containers/common v0.44.0 `pkg/config/config.go`** — re-confirmed `systemConfigs()` + `rootlessConfigPath()` paths
- **Ubuntu Manpage ch-image** — confirmed `APT::Sandbox::User "root"` approach
- **DuckDuckGo search results** — confirmed `APT::Sandbox::User` disables privilege dropping, `/etc/apt/apt.conf.d/99sandbox` is the standard location

## DinD Rootless Fixes (Phase 8 — v0.1.6, chown sub-UID mapping)

### Problem
v0.1.5 apt-get fix WORKED, but user's Spring Boot Dockerfile `RUN chown -R appuser:appgroup /app /logs` fails with "Invalid argument" (EINVAL) on every file. Root cause: single-UID user namespace mapping. With `_CONTAINERS_USERNS_CONFIGURED=1`, `MaybeReexecUsingUserNamespace()` returns early → only UID 0 maps to host UID 1001 → `lchown()` to UID 999 (appuser) returns EINVAL because that UID doesn't exist in the mapping.

### Fix in v0.1.6
1. **Installed `uidmap` package** — provides `newuidmap`/`newgidmap` with suid bit for mapping 65536 UIDs from `/etc/subuid`
2. **Belt-and-suspenders suid** — `chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap`
3. **Auto-detection in wrapper scripts** — checks `/proc/self/status` for `NoNewPrivs:.*0` AND suid bit on newuidmap/newgidmap:
   - If BOTH pass (Track C: `allowPrivilegeEscalation: true` + SETUID/SETGID caps) → `unset _CONTAINERS_USERNS_CONFIGURED` → `MaybeReexecUsingUserNamespace()` creates full mapping (0:1001:1 + 1:100000:65535) → chown to arbitrary UIDs works
   - If EITHER fails (Track A: strict non-root) → keeps `_CONTAINERS_USERNS_CONFIGURED=1` → single-UID fallback
4. **Wrapper scripts refactored** — moved from inline `printf` to separate files `wrappers/*.sh`, COPY'd into image. Cleaner, easier to maintain.
5. **Track C Helm values documented** — `helm/runner-values-dind.yaml` Track C section updated with clear explanation of chown requirement

### Key technical details
- `NoNewPrivs: 0` in `/proc/self/status` means `allowPrivilegeEscalation: true` → suid binaries can escalate → newuidmap works
- `NoNewPrivs: 1` means `no_new_privs` kernel flag set → suid blocked → single-UID fallback
- Wrapper detection: `grep -q 'NoNewPrivs:.*0' /proc/self/status && [ -u /usr/bin/newuidmap ] && [ -u /usr/bin/newgidmap ]`
- When `_CONTAINERS_USERNS_CONFIGURED` is unset, containers/storage `MaybeReexecUsingUserNamespace()` re-execs buildah/podman in user namespace with full UID map from `/etc/subuid` (`runner:100000:65536`)
- Inside that namespace, buildah chroot isolation inherits the parent's UID mapping (no CLONE_NEWUSER needed) → all UIDs 0-65535 are valid → `lchown(file, 999, 999)` succeeds

### Image pushed
- `docker.io/annepdevops/actions-runner-dind:0.1.6-s390x` — v0.1.6, uidmap + sub-UID auto-detection. Digest: `sha256:577ed5e8f4bf47cdcca2f1ac4e9cb96b006232fa3637b80a9107252d51e662c3`.

### Files updated
- `docker/runner-s390x-dind/Dockerfile` — storage.conf global `[storage.options]` + direct wrapper scripts
- `.env.example` — `IMAGE_TAG=0.1.3-s390x`
- `docs/test-dind-pod.yaml` — image tag bumped to v0.1.3
- `scripts/test-dind-rootless.sh` — image tag bumped to v0.1.3
- Red Hat OpenShift Pipelines docs: unprivileged buildah — SETUID/SETGID + allowPrivilegeEscalation pattern.
- buildah GitHub issue #4049 / discussion #5720 — `cat /proc/self/uid_map` diagnosis.
- oneuptime blog: rootless buildah in Kubernetes CI — VFS + chroot + SETUID/SETGID caps pattern.
- buildah tutorial 05: OpenShift rootless with anyuid SCC.
- Ubuntu 22.04 packages database — confirmed podman 3.4.4, buildah 1.23.1, containers-common 0.44.

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
