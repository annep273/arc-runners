#!/bin/sh
# ── buildah wrapper ──────────────────────────────────────────────────
# Installed at /usr/local/bin/buildah (PATH priority over /usr/bin/buildah).
# Runs buildah inside a user namespace to eliminate newuidmap warnings.
#
# WHY UNSHARE:
#   buildah's MaybeReexecUsingUserNamespace() in main() runs on EVERY
#   command (login, images, inspect, bud — everything). When euid != 0,
#   it ALWAYS tries to re-exec with newuidmap/newgidmap. The env var
#   _CONTAINERS_USERNS_CONFIGURED only prevents the re-exec'd CHILD
#   from looping — it does NOT prevent the initial attempt.
#
#   In enterprise k8s, newuidmap always fails (SELinux/seccomp/CRI-O
#   blocking /proc/*/gid_map writes), producing noisy warnings:
#     "error running newgidmap: exit status 1"
#     "falling back to single mapping"
#
#   Fix: unshare --user --map-root-user creates a user namespace where
#   euid=0 (mapped to host UID 1001). MaybeReexecUsingUserNamespace()
#   checks: euid==0 && IsRootless() → true → returns immediately.
#   No re-exec, no newuidmap attempt, no warnings.
#
# MOUNT INJECTION:
#   buildah reads /usr/share/containers/mounts.conf by default and
#   injects these into every build container:
#   - APT sandbox config (prevents setgroups errors)
#   - chown/chgrp shell shims (intercept shell commands)
#   - fakechown.so + ld.so.preload (intercept libc chown calls)
#
# NOTES on buildah 1.23.1:
#   --storage-driver, --storage-opt → global (PersistentFlags)
#   --isolation is NOT global — use BUILDAH_ISOLATION=chroot env var
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

export _CONTAINERS_USERNS_CONFIGURED=1

exec unshare --user --map-root-user -- /usr/bin/buildah \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
