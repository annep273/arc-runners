#!/bin/sh
# ── podman wrapper ───────────────────────────────────────────────────
# Installed at /usr/local/bin/podman (PATH priority over /usr/bin/podman).
# Runs podman inside a user namespace to eliminate newuidmap warnings.
#
# See buildah-wrapper.sh for the detailed explanation of why unshare
# is needed: MaybeReexecUsingUserNamespace() always tries newuidmap
# when euid != 0, regardless of _CONTAINERS_USERNS_CONFIGURED.
# unshare --user --map-root-user makes euid=0 → function returns early.
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

exec unshare --user --map-root-user -- /usr/bin/podman \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
