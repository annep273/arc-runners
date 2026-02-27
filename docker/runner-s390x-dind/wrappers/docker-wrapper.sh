#!/bin/sh
# ── docker wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/docker (PATH priority).
# Maps 'docker' commands to podman inside a user namespace.
# Standard docker-based CI steps work without modification.
#
# See buildah-wrapper.sh for the unshare explanation.
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

export _CONTAINERS_USERNS_CONFIGURED=1

exec unshare --user --map-root-user -- /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
