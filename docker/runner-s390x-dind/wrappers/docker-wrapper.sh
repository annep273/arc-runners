#!/bin/sh
# ── docker wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/docker (PATH priority).
# Maps 'docker' commands to podman with explicit VFS flags.
# Standard docker-based CI steps work without modification.
#
# See buildah-wrapper.sh for why we do NOT use unshare.
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

export _CONTAINERS_USERNS_CONFIGURED=1

exec /usr/bin/podman \
  --log-level error \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
