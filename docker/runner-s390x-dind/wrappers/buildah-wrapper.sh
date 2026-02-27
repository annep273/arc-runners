#!/bin/sh
# ── buildah wrapper ──────────────────────────────────────────────────
# Installed at /usr/local/bin/buildah (PATH priority over /usr/bin/buildah).
# Adds VFS storage flags, default-mounts-file, and auto-detects sub-UID.
#
# See podman-wrapper.sh for detailed documentation on symlink repair
# and sub-UID detection logic.
#
# NOTES on buildah 1.23.1:
#   --storage-driver, --storage-opt  → global (PersistentFlags)
#   --default-mounts-file            → global (PersistentFlag)
#   --isolation is NOT global — use BUILDAH_ISOLATION=chroot env var.
#
# --default-mounts-file injects apt sandbox config into build containers
# so RUN apt-get steps work without modification in rootless builds.
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

exec /usr/bin/buildah \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  --default-mounts-file=/usr/share/containers/mounts.conf \
  "$@"
