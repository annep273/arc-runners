#!/bin/sh
# ── docker wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/docker (PATH priority).
# Maps 'docker' commands to podman with correct storage flags.
# Standard docker-based CI steps work without modification.
#
# See podman-wrapper.sh for documentation on symlink repair and why
# _CONTAINERS_USERNS_CONFIGURED is always kept set.
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

# Ensure _CONTAINERS_USERNS_CONFIGURED stays set (prevents newuidmap attempts)
export _CONTAINERS_USERNS_CONFIGURED=1

exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
