#!/bin/sh
# ── podman wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/podman (PATH priority over /usr/bin/podman).
# Runs podman with explicit VFS + ignore_chown_errors flags.
#
# See buildah-wrapper.sh for detailed explanation of why we do NOT use
# 'unshare --user --map-root-user' (root config paths → /root/.config/
# permission denied). Rootless mode (euid=1001) works correctly.
#
# SYMLINK REPAIR:
#   ARC or workflow steps may overwrite the user-level containers.conf
#   symlink with a file containing keys unknown to podman 3.4.4
#   (e.g. network_backend). We recreate the symlink before every call.
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
