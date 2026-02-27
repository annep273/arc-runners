#!/bin/sh
# ── docker wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/docker (PATH priority).
# Maps 'docker' commands to podman with correct storage flags.
# Standard docker-based CI steps work without modification.
#
# See podman-wrapper.sh for detailed documentation on symlink repair
# and sub-UID detection logic.
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

# Auto-detect sub-UID mapping (see podman-wrapper.sh for details)
if grep -q 'NoNewPrivs:.*0' /proc/self/status 2>/dev/null && \
   [ -u /usr/bin/newuidmap ] && [ -u /usr/bin/newgidmap ]; then
  unset _CONTAINERS_USERNS_CONFIGURED
fi

exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
