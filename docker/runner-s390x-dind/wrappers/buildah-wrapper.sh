#!/bin/sh
# ── buildah wrapper ──────────────────────────────────────────────────
# Installed at /usr/local/bin/buildah (PATH priority over /usr/bin/buildah).
# Runs buildah with explicit VFS + ignore_chown_errors flags.
#
# HOW IT WORKS:
#   buildah's MaybeReexecUsingUserNamespace() runs at startup and tries
#   to re-exec inside a user namespace (newuidmap/newgidmap). In
#   enterprise k8s these always fail (SELinux/seccomp/CRI-O blocking
#   /proc/*/gid_map writes), so the function falls through and buildah
#   continues running as euid=1001 in plain rootless mode.
#
#   The 2–3 lines of "error running newgidmap" warnings are cosmetic.
#   Our newuidmap/newgidmap stubs (exit 1) keep the messages minimal.
#
#   NOTE: We do NOT use 'unshare --user --map-root-user' here because
#   making euid=0 triggers ROOT config discovery paths in containers/
#   common, which tries to lstat /root/.config/containers/containers.
#   conf.d — inaccessible to host UID 1001 → fatal error.
#   The rootless (euid=1001) code path uses $HOME/.config/ which works.
#
# MOUNT INJECTION:
#   buildah reads /usr/share/containers/mounts.conf and injects:
#   - APT sandbox config (prevents setgroups errors)
#   - chown/chgrp shell shims (intercept shell commands)
#   - fakechown.so + ld.so.preload (intercept libc chown calls)
#
# NOTES on buildah 1.23.1:
#   --storage-driver, --storage-opt, --log-level → global (PersistentFlags)
#   --isolation is NOT global — use BUILDAH_ISOLATION=chroot env var
#   --log-level is parsed AFTER MaybeReexec, so it cannot suppress the
#   newuidmap warnings (those print before cobra parses flags).
# ─────────────────────────────────────────────────────────────────────

# Repair user containers.conf symlink (prevents network_backend warning)
if [ ! -L "$HOME/.config/containers/containers.conf" ] 2>/dev/null; then
  rm -f "$HOME/.config/containers/containers.conf" 2>/dev/null
  ln -sf /etc/containers/containers.conf "$HOME/.config/containers/containers.conf" 2>/dev/null
fi

export _CONTAINERS_USERNS_CONFIGURED=1

exec /usr/bin/buildah \
  --log-level error \
  --storage-driver=vfs \
  --storage-opt vfs.ignore_chown_errors=true \
  "$@"
