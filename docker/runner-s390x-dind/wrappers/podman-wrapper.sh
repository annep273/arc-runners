#!/bin/sh
# ── podman wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/podman (PATH priority over /usr/bin/podman).
# Adds VFS storage flags for rootless container builds.
#
# SYMLINK REPAIR:
#   ARC or workflow steps may overwrite the user-level containers.conf
#   symlink with a file containing keys unknown to podman 3.4.4
#   (e.g. network_backend). We recreate the symlink before every call.
#
# _CONTAINERS_USERNS_CONFIGURED=1:
#   Kept set ALWAYS. We previously tried auto-detecting sub-UID mapping
#   capability by checking NoNewPrivs + suid bits on newuidmap. However,
#   even when those checks pass, newuidmap can STILL fail due to:
#     - SELinux denying /proc/*/gid_map writes
#     - seccomp RuntimeDefault profile restrictions
#     - CRI-O/containerd runtime restrictions
#   When newuidmap fails, containers/storage falls back to single-UID
#   mapping anyway. So we skip the attempt entirely to avoid confusing
#   "Permission denied" warnings in build logs.
#
#   chown/chgrp to non-root UIDs is handled by shim scripts injected
#   into build containers via mounts.conf (see chown-shim.sh).
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
