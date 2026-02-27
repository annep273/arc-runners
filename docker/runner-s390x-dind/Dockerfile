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
#   - _CONTAINERS_USERNS_CONFIGURED=1 bypasses newuidmap/newgidmap
#   - ignore_chown_errors=true handles single-UID mapping
#   - ALL system-level configs replaced (not just user-level) to prevent
#     podman 3.4.4 from reading unknown TOML keys shipped by Ubuntu 22.04's
#     containers-common package (e.g. network.network_backend)
#   - All writable paths under /tmp or /home/runner (no /run access needed)
#
# KNOWN ISSUE: Ubuntu 22.04 ships podman 3.4.4 / buildah 1.23.1, which are
# from late 2021. The containers-common package may ship config files with
# TOML keys added in later versions (e.g. network_backend). These cause
# "Failed to decode" warnings/errors. We fix this by replacing ALL config
# files at the system level.
#
# For overlay storage with full user-namespace support, set in Helm values:
#   hostUsers: false  (k8s 1.30+)  -OR-
#   allowPrivilegeEscalation: true + capabilities: {add: [SETUID, SETGID]}
#
# Build command:
#   docker buildx build --platform linux/s390x \
#     --build-arg BASE_IMAGE=<registry>/actions-runner:<tag> \
#     -t <registry>/actions-runner-dind:<tag> --push .

ARG BASE_IMAGE=annepdevops/actions-runner:0.1.0-s390x

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

# ── Default mounts for buildah builds ────────────────────────────────
# mounts.conf tells buildah to auto-inject files into every container
# it builds (via setupMounts → subscriptions.MountsWithUIDGID).
# This injects the apt sandbox config into Debian/Ubuntu build containers
# so RUN apt-get commands work without modification.
# For non-Debian containers, the file is harmlessly present.
# Source: containers/common pkg/subscriptions/subscriptions.go
RUN echo '/etc/apt/apt.conf.d/99sandbox:/etc/apt/apt.conf.d/99sandbox' \
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
#   Tells containers/storage to skip newuidmap/newgidmap entirely.
#   Prevents "cannot setup namespace using newuidmap" errors.
#   Works with podman 3.4.4's containers/storage library.
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

# ── Wrapper scripts with explicit CLI flags ──────────────────────────
# Belt-and-suspenders: env vars (STORAGE_DRIVER, STORAGE_OPTS,
# BUILDAH_ISOLATION) already configure everything. These wrappers add
# explicit CLI flags as a safety net in case env vars are cleared.
#
# IMPORTANT for buildah 1.23.1:
#   --storage-driver, --storage-opt ARE global (PersistentFlags)
#   --default-mounts-file IS a global flag (PersistentFlag)
#   --isolation is NOT a global flag — it's only valid on subcommands
#   (bud, from, run). Use BUILDAH_ISOLATION=chroot env var instead.
#
# The VFS driver requires 'vfs.' prefix on options:
#   Valid:   vfs.ignore_chown_errors=true
#   Invalid: ignore_chown_errors=true  (causes "does not support" error)
#
# Each wrapper also repairs the user-level containers.conf symlink
# before every invocation. This prevents "Failed to decode the keys
# [network.network_backend]" warnings caused by ARC or workflow steps
# creating a user containers.conf with keys unknown to podman 3.4.4.
#
# We do NOT force --root/--runroot here — storage paths come from
# CONTAINERS_STORAGE_CONF or the workflow's own storage.conf.
# This avoids conflicts with workflows that configure their own paths.
RUN printf '#!/bin/sh\n# Repair user containers.conf symlink (prevents network_backend warning)\nif [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then\n  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null\n  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null\nfi\nexec /usr/bin/podman \\\n  --storage-driver=vfs \\\n  --storage-opt vfs.ignore_chown_errors=true \\\n  "$@"\n' > /usr/local/bin/podman && chmod +x /usr/local/bin/podman

RUN printf '#!/bin/sh\n# Repair user containers.conf symlink (prevents network_backend warning)\nif [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then\n  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null\n  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null\nfi\n# NOTE: --isolation is NOT a global buildah flag.\n# Use BUILDAH_ISOLATION=chroot env var (already set in image).\n# --default-mounts-file injects apt sandbox config into build containers.\nexec /usr/bin/buildah \\\n  --storage-driver=vfs \\\n  --storage-opt vfs.ignore_chown_errors=true \\\n  --default-mounts-file=/usr/share/containers/mounts.conf \\\n  "$@"\n' > /usr/local/bin/buildah && chmod +x /usr/local/bin/buildah

RUN printf '#!/bin/sh\n# Repair user containers.conf symlink (prevents network_backend warning)\nif [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then\n  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null\n  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null\nfi\nexec /usr/bin/podman \\\n  --storage-driver=vfs \\\n  --storage-opt vfs.ignore_chown_errors=true \\\n  "$@"\n' > /usr/local/bin/docker && chmod +x /usr/local/bin/docker

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
