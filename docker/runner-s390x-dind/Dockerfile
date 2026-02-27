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
#   - All writable paths under /tmp or /home/runner (no /run access needed)
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
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/podman /usr/local/bin/docker

# ── Environment for rootless container-in-container ──────────────────
# BUILDAH_ISOLATION=chroot:
#   Avoids runc/crun which require user namespaces or root.
#   chroot isolation works in unprivileged pods.
#
# _CONTAINERS_USERNS_CONFIGURED=1:
#   Tells podman/buildah to skip newuidmap/newgidmap setup entirely.
#   Prevents "cannot setup namespace using newuidmap" errors.
#
# STORAGE_DRIVER=vfs:
#   Most compatible driver. No kernel module or fuse dependencies.
#   Works with single-UID mapping (restricted SCC).
#
# XDG_RUNTIME_DIR:
#   Must point to a writable directory. Default /run/user/1001 does not
#   exist in Kubernetes pods. We create it under /tmp.
ENV BUILDAH_ISOLATION=chroot \
    _CONTAINERS_USERNS_CONFIGURED=1 \
    STORAGE_DRIVER=vfs \
    XDG_RUNTIME_DIR=/tmp/xdg-run-1001

# ── Storage configuration (VFS — most compatible) ────────────────────
# runroot: Temporary runtime data. MUST be writable.
#   Default /run/containers is NOT writable in pods → use /tmp.
# graphroot: Persistent image/layer storage.
#   Use home dir so it survives across build steps.
# ignore_chown_errors: Required when running with single UID mapping
#   (no user namespace). Files in pulled images get squashed to UID 1001.
RUN mkdir -p /home/runner/.config/containers && \
    cat > /home/runner/.config/containers/storage.conf <<'EOF'
[storage]
driver = "vfs"
runroot = "/tmp/containers-run-1001"
graphroot = "/home/runner/.local/share/containers/storage"

[storage.options]
pull_options = {enable_partial_images = "false", use_hard_links = "false", ostree_repos=""}

[storage.options.overlay]
ignore_chown_errors = "true"
mount_program = "/usr/bin/fuse-overlayfs"

[storage.options.vfs]
ignore_chown_errors = "true"
EOF

# ── containers.conf — disable network-related features ───────────────
# In chroot isolation, network namespaces are not created.
# Suppress "Failed to decode network.network_backend" warnings by
# not setting that key at all. cni is the default on Ubuntu 22.04 podman.
RUN cat > /home/runner/.config/containers/containers.conf <<'EOF'
[containers]
log_driver = "k8s-file"
env = ["BUILDAH_ISOLATION=chroot"]

[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
runtime = "crun"
EOF

# ── Registry configuration ───────────────────────────────────────────
RUN cat > /home/runner/.config/containers/registries.conf <<'EOF'
[registries.search]
registries = ['docker.io']

[registries.insecure]
registries = []
EOF

# ── policy.json — required for image pulls (often missing in minimal images)
RUN mkdir -p /etc/containers && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

# Set up subuid/subgid for when user namespaces ARE available
# (e.g., hostUsers: false in k8s 1.30+ or SETUID/SETGID caps).
# When _CONTAINERS_USERNS_CONFIGURED=1, these are ignored.
RUN echo "runner:100000:65536" >> /etc/subuid && \
    echo "runner:100000:65536" >> /etc/subgid

# ── Create all writable runtime directories ──────────────────────────
# These must exist before the container starts as UID 1001 cannot
# create directories under /tmp at image build time in some runtimes.
RUN mkdir -p /tmp/xdg-run-1001 && \
    mkdir -p /tmp/containers-run-1001 && \
    mkdir -p /home/runner/.local/share/containers/storage && \
    chown -R runner:docker /tmp/xdg-run-1001 && \
    chown -R runner:docker /tmp/containers-run-1001 && \
    chown -R runner:docker /home/runner/.config && \
    chown -R runner:docker /home/runner/.local

USER 1001

ENTRYPOINT ["/home/runner/run.sh"]
