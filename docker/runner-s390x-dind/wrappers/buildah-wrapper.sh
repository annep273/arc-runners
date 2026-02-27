#!/bin/sh
# ── buildah wrapper ──────────────────────────────────────────────────
# Installed at /usr/local/bin/buildah (PATH priority over /usr/bin/buildah).
# Adds VFS storage flags and default-mounts-file for rootless builds.
#
# See podman-wrapper.sh for documentation on symlink repair and why
# _CONTAINERS_USERNS_CONFIGURED is always kept set.
#
# NOTES on buildah 1.23.1:
#   --storage-driver, --storage-opt  → global (PersistentFlags)
#   --default-mounts-file            → global (PersistentFlag)
#   --isolation is NOT global — use BUILDAH_ISOLATION=chroot env var.
#
# --default-mounts-file injects into EVERY build container:
#   - apt sandbox config (prevents setgroups errors in apt-get)
#   - chown shim (silently succeeds when chown hits EINVAL/EPERM)
#   - chgrp shim (same for chgrp)
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

# Ensure _CONTAINERS_USERNS_CONFIGURED stays set (prevents newuidmap attempts)
export _CONTAINERS_USERNS_CONFIGURED=1

exec /usr/bin/buildah \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  --default-mounts-file=/usr/share/containers/mounts.conf \
  "$@"
