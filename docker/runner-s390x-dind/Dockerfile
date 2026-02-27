# ARC Runner image with container-build tooling for linux/s390x
# Extends the base runner image with podman/buildah/skopeo for workflows that
# build container images. On OpenShift, podman is the preferred runtime
# because DinD (Docker-in-Docker) requires privileged pods which are
# restricted by default SCCs. podman is exposed as 'docker' via a symlink
# so standard docker-based CI steps work without modification.
#
# SECURITY: This image runs as non-root (UID 1001).
#   - VFS storage driver (no kernel overlay/fuse deps; works everywhere)
#   - chroot isolation (no runc/crun user-namespace requirement)
#   - _CONTAINERS_USERNS_CONFIGURED=1 always set (single-UID namespace)
#   - Triple-layer chown protection for single-UID namespace:
#     Layer 1: chown/chgrp shell shims (intercept /usr/bin/chown commands)
#     Layer 2: LD_PRELOAD fakechown.so (intercept ALL libc chown syscalls)
#     Layer 3: ignore_chown_errors=true (storage driver layer operations)
#   - All injected via mounts.conf into every build container
#   - ALL system-level configs replaced (not just user-level) to prevent
#     podman 3.4.4 from reading unknown TOML keys shipped by Ubuntu 22.04's
#     containers-common package (e.g. network.network_backend)
#   - newuidmap/newgidmap neutered (fail silently in enterprise k8s anyway)
#   - /root/ made accessible for safety (root config path contingency)
#   - All writable paths under /tmp or /home/runner (no /run access needed)
#
# PERMISSION FAILURE COVERAGE:
#   ✅ RUN chown/chgrp        → shell shims (mounts.conf bind mount)
#   ✅ RUN useradd -m          → LD_PRELOAD fakechown.so
#   ✅ RUN tar --same-owner    → LD_PRELOAD fakechown.so
#   ✅ RUN install -o          → LD_PRELOAD fakechown.so
#   ✅ RUN cp --preserve       → LD_PRELOAD fakechown.so
#   ✅ RUN apt-get install     → APT sandbox + LD_PRELOAD for dpkg chown
#   ✅ VFS layer extraction    → ignore_chown_errors=true
#   ⚠️ COPY --chown=user      → Go raw syscall, NOT interceptable*
#   ⚠️ Alpine/musl images     → shell shims work, LD_PRELOAD may not
#   ℹ️ newuidmap warnings     → replaced with silent stubs (cosmetic only)
#   ℹ️ --log-level error      → suppresses XDG_RUNTIME_DIR + other warnings
#
#   * Workaround: use COPY + RUN chown instead of COPY --chown
#
# Build command:
#   docker buildx build --platform linux/s390x \
#     --build-arg BASE_IMAGE=<registry>/actions-runner:<tag> \
#     -t <registry>/actions-runner-dind:<tag> --push .

ARG BASE_IMAGE=annepdevops/actions-runner:0.1.0-s390x

# ── Stage 1: Compile fakechown.so for LD_PRELOAD injection ──────────
# This shared library intercepts chown/lchown/fchown/fchownat libc calls
# inside build containers. Tries real implementation first; suppresses
# EINVAL (UID not mapped) and EPERM (no CAP_CHOWN) silently.
# Covers: useradd -m, tar --same-owner, install -o, cp --preserve, dpkg
# NOT: Go programs (buildah COPY --chown uses raw syscalls, not libc)
FROM ubuntu:22.04 AS fakechown-builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*
COPY wrappers/fakechown.c /tmp/fakechown.c
RUN gcc -shared -fPIC -o /tmp/fakechown.so /tmp/fakechown.c -ldl

# ── Stage 2: Main runner image ──────────────────────────────────────
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="ARC Self-Hosted Runner DinD (s390x)" \
      org.opencontainers.image.description="Non-root container-build runner with podman/buildah for linux/s390x"

USER root

# ── Install container-build tooling ──────────────────────────────────
# podman replaces Docker for container-build workflows on OpenShift/s390x.
# skopeo is used for image inspection and registry operations.
# buildah is the OCI image build tool.
#
# NOTE: The base image is Ubuntu 22.04, so we use apt-get (not microdnf).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      podman \
      buildah \
      skopeo \
      fuse-overlayfs \
      iptables \
      slirp4netns && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Neuter newuidmap/newgidmap ───────────────────────────────────────
# These are pulled in by the uidmap package (dependency of podman).
# In enterprise k8s, they ALWAYS fail due to SELinux/seccomp/CRI-O
# blocking writes to /proc/*/gid_map, producing noisy warnings:
#   "error running newgidmap: ... Permission denied"
#   "falling back to single mapping"
# Replace with silent stubs that exit 1 immediately. containers/storage
# sees exit 1 and falls back to single-UID mapping (the correct behavior).
RUN printf '#!/bin/sh\nexit 1\n' > /usr/bin/newuidmap && \
    printf '#!/bin/sh\nexit 1\n' > /usr/bin/newgidmap && \
    chmod 755 /usr/bin/newuidmap /usr/bin/newgidmap

# ── Safety net: make /root/.config/ accessible ──────────────────────
# Ubuntu backports add containers.conf.d directory scanning. If buildah
# ever runs as euid=0 in a user namespace (e.g. MaybeReexecUsingUserNamespace
# succeeds), config loading tries to lstat /root/.config/containers/
# containers.conf.d. Host UID 1001 (mapped to euid=0) can't traverse /root/
# (mode 0700, owned by real root) → EACCES → fatal config error.
# Making /root/ world-traversable (755) prevents this. The directory is
# empty in our image so there's no security concern.
RUN chmod 755 /root && \
    mkdir -p /root/.config/containers/containers.conf.d

# ── CRITICAL: Replace ALL system-level config files ──────────────────
# Ubuntu 22.04's containers-common package ships config files that may
# contain TOML keys not understood by the older podman 3.4.4 / buildah 1.23.1
# binaries (e.g. network.network_backend added in containers/common ~v0.47+).
# The TOML decoder logs "Failed to decode the keys ..." for these.
#
# Config precedence (containers/storage types/options.go):
#   1. /usr/share/containers/storage.conf  (package default)
#   2. /etc/containers/storage.conf        (override — takes priority if exists)
#   3. $CONTAINERS_STORAGE_CONF            (env var — ultimate override)
#   4. ~/.config/containers/storage.conf   (rootless user override)
#
# Config precedence (containers/common pkg/config):
#   1. /usr/share/containers/containers.conf
#   2. /etc/containers/containers.conf
#   3. ~/.config/containers/containers.conf (rootless)
#
# We REPLACE all three levels to guarantee no unknown keys are parsed.
# ─────────────────────────────────────────────────────────────────────

# ── System-level storage.conf (/etc/containers/ + /usr/share/containers/)
# Replaces distro defaults. These are read BEFORE user configs.
RUN mkdir -p /etc/containers /usr/share/containers && \
    cat > /etc/containers/storage.conf <<'SCONF'
[storage]
driver = "vfs"
runroot = "/tmp/containers-run-1001"
graphroot = "/home/runner/.local/share/containers/storage"

[storage.options]
# CRITICAL: ignore_chown_errors MUST be at global [storage.options] level
# to be propagated as a DriverOption to the VFS driver init.
# Per-driver subsections ([storage.options.vfs]) may NOT be parsed by
# containers/storage v1.38.2 (shipped with podman 3.4.4).
ignore_chown_errors = "true"
pull_options = {enable_partial_images = "false", use_hard_links = "false", ostree_repos=""}

[storage.options.overlay]
ignore_chown_errors = "true"
mount_program = "/usr/bin/fuse-overlayfs"

[storage.options.vfs]
ignore_chown_errors = "true"
SCONF

# Copy same config to /usr/share/containers/ (package-default location)
RUN cp /etc/containers/storage.conf /usr/share/containers/storage.conf

# ── System-level containers.conf ─────────────────────────────────────
# IMPORTANT: Only use TOML keys known to podman 3.4 / containers-common v0.44.
# DO NOT include: network_backend, netavark_plugin_dirs, pasta_binary, etc.
# DO NOT include [secrets] or [secrets.opts] — these may cause parse errors
# on the old library version.
RUN cat > /etc/containers/containers.conf <<'CCONF'
[containers]
log_driver = "k8s-file"
env = ["BUILDAH_ISOLATION=chroot", "_CONTAINERS_USERNS_CONFIGURED=1"]
userns = "host"
netns = "host"
ipcns = "host"
utsns = "host"
cgroupns = "host"

[network]
# Only keys valid in containers/common v0.44 (podman 3.4):
# cni_plugin_dirs, default_network, default_subnet, network_config_dir
# NO network_backend — that key was added later and causes decode errors.
network_config_dir = "/etc/cni/net.d/"

[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
runtime = "crun"
no_pivot_root = true
CCONF

# Copy same config to /usr/share/containers/
RUN cp /etc/containers/containers.conf /usr/share/containers/containers.conf

# ── System-level registries.conf ─────────────────────────────────────
RUN cat > /etc/containers/registries.conf <<'RCONF'
[registries.search]
registries = ['docker.io']

[registries.insecure]
registries = []

[registries.block]
registries = []
RCONF

RUN cp /etc/containers/registries.conf /usr/share/containers/registries.conf

# ── policy.json — required for image pulls ───────────────────────────
RUN echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

# ── APT sandbox workaround for rootless builds ──────────────────────
# When buildah builds Debian/Ubuntu images with chroot isolation,
# apt-get tries to drop privileges to _apt user via setgroups(65534).
# This fails because:
#   1. The kernel sets /proc/PID/setgroups to "deny" in unprivileged
#      user namespaces (security requirement before writing gid_map)
#   2. With chroot isolation + single-UID mapping, there's no way to
#      call setgroups() or seteuid() to switch to other UIDs/GIDs
# Fix: APT::Sandbox::User "root" tells apt to skip privilege dropping.
# Since we're already unprivileged, there's nothing to drop.
RUN mkdir -p /etc/apt/apt.conf.d && \
    echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/99sandbox

# ── chown/chgrp shims for rootless builds ─────────────────────────
# In rootless builds with single-UID namespace mapping, chown/chgrp
# to any UID/GID other than 0 fails (EINVAL or EPERM). This is a kernel
# limitation: the target UID simply doesn't exist in the namespace.
#
# These shim scripts are injected into EVERY build container via
# mounts.conf (bind-mounted at /usr/local/bin/chown and /usr/local/bin/chgrp).
# /usr/local/bin is earlier in PATH than /usr/bin, so the shims intercept
# chown/chgrp commands. Each shim:
#   1. Finds the real binary (/usr/bin/chown or /bin/chown)
#   2. Runs it with the original arguments
#   3. If it fails with "Invalid argument" or "Operation not permitted",
#      silently succeeds (exit 0)
#   4. For any other error, propagates it normally
#
# This handles the common Dockerfile pattern:
#   RUN groupadd appgroup && useradd appuser
#   RUN chown -R appuser:appgroup /app /logs
#
# Files retain ownership of UID 0 (root inside the build namespace,
# which maps to runner UID 1001 on the host). This is safe for
# containerized apps — the USER instruction controls runtime UID.
COPY wrappers/chown-shim.sh /usr/local/share/containers/chown-shim.sh
COPY wrappers/chgrp-shim.sh /usr/local/share/containers/chgrp-shim.sh
RUN chmod +x /usr/local/share/containers/chown-shim.sh \
             /usr/local/share/containers/chgrp-shim.sh

# ── LD_PRELOAD library for comprehensive chown interception ──────────
# The shell shims above only cover explicit chown/chgrp commands.
# Many programs call chown() via libc directly (useradd, tar, install,
# dpkg, cp --preserve). The LD_PRELOAD library intercepts ALL libc
# chown/lchown/fchown/fchownat calls, tries real implementation first,
# suppresses EINVAL/EPERM silently.
#
# Injected into build containers via mounts.conf:
#   fakechown.so → /usr/local/lib/fakechown.so
#   ld.so.preload → /etc/ld.so.preload (tells dynamic linker to load .so)
#
# NOTE: Does NOT intercept Go programs (buildah, podman) which use raw
# syscalls. buildah COPY --chown uses Go's os.Lchown() → raw SYS_LCHOWN.
# Workaround: use COPY + RUN chown instead of COPY --chown.
COPY --from=fakechown-builder /tmp/fakechown.so /usr/local/share/containers/fakechown.so
COPY wrappers/ld.so.preload /usr/local/share/containers/ld.so.preload

# ── Default mounts for buildah builds ────────────────────────────
# mounts.conf tells buildah to auto-inject files into every container
# it builds (via setupMounts → subscriptions.MountsWithUIDGID).
# Entries are source:destination bind mounts.
#
# Injected files:
#   1. APT sandbox config — prevents setgroups errors in apt-get
#   2. chown shim — intercepts /usr/bin/chown commands
#   3. chgrp shim — intercepts /usr/bin/chgrp commands
#   4. fakechown.so — LD_PRELOAD library intercepting libc chown syscalls
#   5. ld.so.preload — tells dynamic linker to load fakechown.so
#
# Together, entries 2-5 provide triple-layer chown protection:
#   Shell shims: RUN chown, RUN chgrp (all distros including Alpine)
#   LD_PRELOAD:  useradd -m, tar, install, cp, dpkg (glibc distros)
#   storage.conf: VFS layer extraction (buildah internal)
#
# Source: containers/common pkg/subscriptions/subscriptions.go
RUN printf '%s\n' \
      '/etc/apt/apt.conf.d/99sandbox:/etc/apt/apt.conf.d/99sandbox' \
      '/usr/local/share/containers/chown-shim.sh:/usr/local/bin/chown' \
      '/usr/local/share/containers/chgrp-shim.sh:/usr/local/bin/chgrp' \
      '/usr/local/share/containers/fakechown.so:/usr/local/lib/fakechown.so' \
      '/usr/local/share/containers/ld.so.preload:/etc/ld.so.preload' \
      > /usr/share/containers/mounts.conf

# ── User-level configs (symlinked to system for safety) ──────────────
# When running as UID 1001, podman reads user configs AFTER system configs.
# ARC or workflow steps may create ~/.config/containers/containers.conf
# with keys not understood by podman 3.4.4 (e.g. network_backend).
# Using SYMLINKS ensures the user config always points to our clean
# system config. If something overwrites the symlink, the wrapper
# scripts will recreate it before each invocation.
RUN mkdir -p /home/runner/.config/containers && \
    cp /etc/containers/storage.conf    /home/runner/.config/containers/storage.conf && \
    ln -sf /etc/containers/containers.conf /home/runner/.config/containers/containers.conf && \
    cp /etc/containers/registries.conf /home/runner/.config/containers/registries.conf

# ── Environment for rootless container-in-container ──────────────────
#
# BUILDAH_ISOLATION=chroot:
#   Avoids runc/crun which require user namespaces or root.
#   chroot isolation works in unprivileged pods. Prevents:
#     - "/" is not a shared mount
#     - cannot setup namespace using newuidmap
#
# _CONTAINERS_USERNS_CONFIGURED=1:
#   ALWAYS set. Tells containers/storage to skip MaybeReexecUsingUserNamespace().
#   newuidmap/newgidmap are replaced with silent stubs (exit 1) since they
#   always fail in enterprise k8s (SELinux/seccomp/CRI-O restrictions).
#   Wrapper scripts also export this explicitly to prevent env drift.
#   chown/chgrp to non-root UIDs is handled by:
#     - Shell shims (mounts.conf → /usr/local/bin/chown, /usr/local/bin/chgrp)
#     - LD_PRELOAD fakechown.so (mounts.conf → /usr/local/lib/fakechown.so)
#     - ignore_chown_errors=true in storage.conf (VFS layer operations)
#
# STORAGE_DRIVER=vfs:
#   Most compatible driver. No kernel module or fuse dependencies.
#   Checked by containers/storage getRootlessStorageOpts() directly.
#
# CONTAINERS_STORAGE_CONF:
#   Forces containers/storage to read OUR config file, bypassing
#   the default discovery at /usr/share and /etc. Ultimate override.
#
# CONTAINERS_REGISTRIES_CONF:
#   Forces registries config path.
#
# CONTAINERS_CONF:
#   Forces containers/common to read ONLY our containers.conf file.
#   When set, systemConfigs() returns ONLY this path — skipping
#   /usr/share/containers/containers.conf, /etc/containers/containers.conf,
#   AND ~/.config/containers/containers.conf. This prevents workflows
#   from creating a user-level containers.conf with keys like
#   network_backend that podman 3.4.4 doesn't understand.
#   Source: containers/common v0.44 pkg/config/config.go systemConfigs()
#
# STORAGE_OPTS=vfs.ignore_chown_errors=true:
#   Directly sets GraphDriverOptions via env var. The 'vfs.' prefix is
#   REQUIRED — containers/storage v1.38.2 VFS driver parseOptions()
#   only accepts '.ignore_chown_errors' or 'vfs.ignore_chown_errors'.
#   Without the prefix, the driver returns:
#     "vfs driver does not support ignore_chown_errors options"
#   Note: STORAGE_OPTS REPLACES all config-file GraphDriverOptions.
#   For VFS, ignore_chown_errors is the only relevant option, so this
#   is safe. Source: types/options.go ReloadConfigurationFile()
#
# XDG_RUNTIME_DIR:
#   Must point to a writable directory. Default /run/user/1001 does not
#   exist in Kubernetes pods. We create it under /tmp.
#
# HOME:
#   Explicit to ensure ~/.config/containers/ resolves correctly.
ENV BUILDAH_ISOLATION=chroot \
    _CONTAINERS_USERNS_CONFIGURED=1 \
    STORAGE_DRIVER=vfs \
    CONTAINERS_STORAGE_CONF=/etc/containers/storage.conf \
    CONTAINERS_REGISTRIES_CONF=/etc/containers/registries.conf \
    CONTAINERS_CONF=/etc/containers/containers.conf \
    STORAGE_OPTS=vfs.ignore_chown_errors=true \
    XDG_RUNTIME_DIR=/tmp/xdg-run-1001 \
    HOME=/home/runner

# ── Set up subuid/subgid ─────────────────────────────────────────────
# For when user namespaces ARE available (hostUsers: false in k8s 1.30+
# or SETUID/SETGID caps). When _CONTAINERS_USERNS_CONFIGURED=1, these
# are ignored — podman skips the namespace setup.
RUN echo "runner:100000:65536" >> /etc/subuid && \
    echo "runner:100000:65536" >> /etc/subgid

# ── Create writable runtime directories ──────────────────────────────
# These must exist and be owned by runner:docker BEFORE switching to
# UID 1001. Kubernetes emptyDir volumes mount over these with correct
# ownership thanks to fsGroup in the pod securityContext, but we create
# them in the image as a fallback for local testing.
RUN mkdir -p /tmp/xdg-run-1001 && \
    mkdir -p /tmp/containers-run-1001 && \
    mkdir -p /home/runner/.local/share/containers/storage && \
    chmod 700 /tmp/xdg-run-1001 && \
    chmod 700 /tmp/containers-run-1001 && \
    chown -R 1001:0 /tmp/xdg-run-1001 && \
    chown -R 1001:0 /tmp/containers-run-1001 && \
    chown -R 1001:0 /home/runner/.config && \
    chown -R 1001:0 /home/runner/.local

# ── Wrapper scripts with --log-level error + explicit CLI flags ────────
# Installed at /usr/local/bin/ (PATH priority over /usr/bin/).
# Source files: wrappers/*.sh (COPY'd into the image).
#
# Each wrapper:
#   1. Repairs user containers.conf symlink (prevents network_backend warning)
#   2. Exports _CONTAINERS_USERNS_CONFIGURED=1
#   3. Runs the real binary with explicit CLI flags:
#        --log-level error (suppress XDG_RUNTIME_DIR + other warnings)
#        --storage-driver=vfs
#        --storage-opt vfs.ignore_chown_errors=true
#
# NOTE ON newuidmap WARNINGS:
#   MaybeReexecUsingUserNamespace() runs BEFORE cobra parses --log-level,
#   so the 2-3 lines of "error running newgidmap" warnings still appear.
#   Our newuidmap/newgidmap stubs (exit 1) keep them minimal. The MaybeReexec
#   attempt fails, buildah continues as euid=1001 in rootless mode, and
#   the build succeeds using $HOME/.config/containers/ config paths.
#
# WHY NOT unshare --user --map-root-user:
#   Making euid=0 triggers ROOT config discovery in containers/common
#   (Ubuntu backportred .conf.d scanning). This tries to lstat
#   /root/.config/containers/containers.conf.d — inaccessible to host
#   UID 1001 → fatal "permission denied" error at RUN step 13.
#   Rootless mode (euid=1001) uses $HOME/.config/ which works correctly.
#
# We do NOT force --root/--runroot — storage paths come from
# CONTAINERS_STORAGE_CONF or the workflow's own storage.conf.
COPY wrappers/podman-wrapper.sh /usr/local/bin/podman
COPY wrappers/buildah-wrapper.sh /usr/local/bin/buildah
COPY wrappers/docker-wrapper.sh /usr/local/bin/docker
RUN chmod +x /usr/local/bin/podman /usr/local/bin/buildah /usr/local/bin/docker

# ── Validate configs at build time ───────────────────────────────────
# Quick sanity check: ensure podman can read the config without errors.
# This runs as root during build but validates TOML parsing.
RUN /usr/bin/podman --storage-driver=vfs \
      --storage-opt vfs.ignore_chown_errors=true \
      --root=/tmp/build-validate \
      --runroot=/tmp/build-validate-run \
      info --format '{{.Store.GraphDriverName}}' 2>&1 | head -20 && \
    rm -rf /tmp/build-validate /tmp/build-validate-run

USER 1001

ENTRYPOINT ["/home/runner/run.sh"]
