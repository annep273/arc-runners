#!/bin/sh
# ── chgrp shim for rootless container builds ─────────────────────────
# Injected at /usr/local/bin/chgrp in build containers via mounts.conf.
# Same logic as chown-shim.sh — see that file for full documentation.
#
# chgrp calls fchownat() with uid=-1 (unchanged) and the target GID.
# In single-UID namespace, any GID other than 0 fails with EINVAL.
# ─────────────────────────────────────────────────────────────────────

REAL_CHGRP=""
for p in /usr/bin/chgrp /bin/chgrp; do
  if [ -x "$p" ]; then
    REAL_CHGRP="$p"
    break
  fi
done

if [ -z "$REAL_CHGRP" ]; then
  exit 0
fi

_out=$("$REAL_CHGRP" "$@" 2>&1)
_rc=$?

if [ "$_rc" -eq 0 ]; then
  [ -n "$_out" ] && printf '%s\n' "$_out"
  exit 0
fi

case "$_out" in
  *"Invalid argument"*|*"Operation not permitted"*)
    exit 0
    ;;
esac

printf '%s\n' "$_out" >&2
exit "$_rc"
