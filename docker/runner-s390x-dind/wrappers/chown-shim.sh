#!/bin/sh
# ── chown shim for rootless container builds ─────────────────────────
# Injected at /usr/local/bin/chown in build containers via mounts.conf.
# /usr/local/bin is earlier in PATH than /usr/bin, so this shim is
# invoked instead of the real coreutils chown.
#
# PURPOSE:
#   In rootless builds with single-UID namespace mapping (the default
#   for ARC runners without special capabilities), chown to any UID
#   other than 0 fails:
#     - EINVAL: UID not mapped in user namespace (single mapping: 0→1001)
#     - EPERM:  Process lacks CAP_CHOWN (no user namespace at all)
#
#   This is a KERNEL limitation that cannot be solved by configuration.
#   The shim intercepts the chown command, runs the real binary, and
#   silently succeeds when the failure is due to UID mapping restrictions.
#
#   Files retain their current ownership (UID 0 in the build namespace,
#   which maps to the runner UID 1001 on the host). For container images,
#   this is generally safe because:
#     - The final image's USER instruction determines the runtime UID
#     - Default umask (022) makes files world-readable
#     - Most containerized apps don't require specific file ownership
#
# SAFETY:
#   - Only suppresses "Invalid argument" (EINVAL) and "Operation not
#     permitted" (EPERM) errors
#   - Real errors (file not found, bad syntax, etc.) are propagated
#   - Works on Ubuntu, Debian, Alpine (busybox), RHEL, etc.
#   - Requires /bin/sh (present in all non-scratch images)
# ─────────────────────────────────────────────────────────────────────

# Find the real chown binary (handles merged /usr and split /usr)
REAL_CHOWN=""
for p in /usr/bin/chown /bin/chown; do
  if [ -x "$p" ]; then
    REAL_CHOWN="$p"
    break
  fi
done

# If no real chown found, succeed silently (minimal/scratch image)
if [ -z "$REAL_CHOWN" ]; then
  exit 0
fi

# Run real chown, capture combined output
_out=$("$REAL_CHOWN" "$@" 2>&1)
_rc=$?

# Success — pass through
if [ "$_rc" -eq 0 ]; then
  [ -n "$_out" ] && printf '%s\n' "$_out"
  exit 0
fi

# Check if failure is due to UID/GID mapping limitation
case "$_out" in
  *"Invalid argument"*|*"Operation not permitted"*)
    # Expected in rootless builds — chown can't change ownership
    # due to single-UID namespace mapping or lack of CAP_CHOWN.
    # Silently succeed. Files keep current ownership (UID 0 in
    # the build namespace).
    exit 0
    ;;
esac

# Other error (file not found, bad syntax, etc.) — propagate
printf '%s\n' "$_out" >&2
exit "$_rc"
