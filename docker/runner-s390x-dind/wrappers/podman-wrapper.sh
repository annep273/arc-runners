#!/bin/sh
# ── podman wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/podman (PATH priority over /usr/bin/podman).
# Adds VFS storage flags and auto-detects sub-UID mapping capability.
#
# SYMLINK REPAIR:
#   ARC or workflow steps may overwrite the user-level containers.conf
#   symlink with a file containing keys unknown to podman 3.4.4
#   (e.g. network_backend). We recreate the symlink before every call.
#
# SUB-UID DETECTION:
#   If newuidmap/newgidmap have suid AND no_new_privs is NOT set
#   (allowPrivilegeEscalation: true in pod spec), we unset
#   _CONTAINERS_USERNS_CONFIGURED so buildah/podman's
#   MaybeReexecUsingUserNamespace() creates a full UID mapping
#   (0:host_uid:1 + 1:100000:65535 from /etc/subuid).
#   This enables chown/chmod to arbitrary UIDs in build containers.
#
#   Without this, only UID 0 is mapped and chown returns EINVAL.
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

# Auto-detect sub-UID mapping capability:
#   1. NoNewPrivs must be 0 (allowPrivilegeEscalation: true → suid works)
#   2. newuidmap and newgidmap must have suid bit set
if grep -q 'NoNewPrivs:.*0' /proc/self/status 2>/dev/null && \
   [ -u /usr/bin/newuidmap ] && [ -u /usr/bin/newgidmap ]; then
  unset _CONTAINERS_USERNS_CONFIGURED
fi

exec /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
