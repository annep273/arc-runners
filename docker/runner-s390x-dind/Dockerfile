# ARC Runner image with container-build tooling for linux/s390x
# Extends the base runner image with podman/buildah/skopeo for workflows that
# build container images. On OpenShift, podman is the preferred runtime
# because DinD (Docker-in-Docker) requires privileged pods which are
# restricted by default SCCs. podman is exposed as 'docker' via a symlink
# so standard docker-based CI steps work without modification.
#
# SECURITY: This image runs as non-root (UID 1001).  Podman operates in
# rootless mode backed by fuse-overlayfs.  No RUNNER_ALLOW_RUNASROOT is set.
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

# podman replaces Docker for container-build workflows on OpenShift/s390x.
# fuse-overlayfs provides rootless overlay storage for podman.
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

# Configure podman for rootless operation as UID 1001
RUN mkdir -p /home/runner/.config/containers && \
    cat > /home/runner/.config/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/1001"
graphroot = "/home/runner/.local/share/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Configure rootless podman registries (use unqualified search for ergonomics)
RUN cat > /home/runner/.config/containers/registries.conf <<'EOF'
[registries.search]
registries = ['docker.io']

[registries.insecure]
registries = []
EOF

# Set up subuid/subgid for rootless user namespace operation
RUN echo "runner:100000:65536" >> /etc/subuid && \
    echo "runner:100000:65536" >> /etc/subgid

# Ensure all config is owned by the runner user
RUN chown -R runner:docker /home/runner/.config && \
    mkdir -p /home/runner/.local/share/containers && \
    chown -R runner:docker /home/runner/.local

USER 1001

ENTRYPOINT ["/home/runner/run.sh"]
