# ARC Runner image with container-build tooling for linux/s390x
# Extends the base runner image with podman/buildah/skopeo for workflows that
# build container images. On OpenShift, podman is the preferred runtime
# because DinD (Docker-in-Docker) requires privileged pods which are
# restricted by default SCCs. podman is exposed as 'docker' via a symlink
# so standard docker-based CI steps work without modification.
#
# Usage note: to use this image in a runner scale set, set containerMode to
# "dind" in values and ensure the namespace SCC allows privileged containers.
#
# Build command:
#   docker buildx build --platform linux/s390x \
#     --build-arg BASE_IMAGE=<registry>/actions-runner:<tag> \
#     -t <registry>/actions-runner-dind:<tag> --push .

ARG BASE_IMAGE=annepdevops/actions-runner:0.1.0-s390x

FROM ${BASE_IMAGE}

USER root

# podman replaces Docker for container-build workflows on OpenShift/s390x.
# fuse-overlayfs provides rootless overlay storage for podman.
# skopeo is used for image inspection and registry operations.
# buildah is the OCI image build tool.
RUN microdnf install -y \
      podman \
      buildah \
      skopeo \
      fuse-overlayfs \
      iptables && \
    microdnf clean all && \
    ln -sf /usr/bin/podman /usr/local/bin/docker

# Configure podman to use fuse-overlayfs as the rootless storage driver
RUN mkdir -p /home/runner/.config/containers && \
    cat > /home/runner/.config/containers/storage.conf <<'EOF'
[storage]
driver = "overlay"
runroot = "/run/user/1001"
graphroot = "/home/runner/.local/share/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

RUN chown -R runner:runner /home/runner/.config

USER 1001

ENTRYPOINT ["/home/runner/run.sh"]
