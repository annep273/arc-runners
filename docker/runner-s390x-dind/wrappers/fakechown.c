/*
 * fakechown.so — LD_PRELOAD library for rootless container builds (s390x)
 *
 * Intercepts chown/lchown/fchown/fchownat libc calls. Tries the real
 * implementation first via dlsym(RTLD_NEXT). If it fails with:
 *   - EINVAL: target UID/GID not mapped in user namespace
 *   - EPERM:  process lacks CAP_CHOWN
 * then returns 0 (success) silently. Other errors propagate normally.
 *
 * COVERAGE (C/C++ programs using libc):
 *   - coreutils:    chown, chgrp, install -o, cp --preserve=ownership
 *   - GNU tar:      extraction with --same-owner (default for root)
 *   - shadow-utils: useradd -m (home directory chown), usermod
 *   - dpkg:         package extraction and postinst scripts
 *   - Python/Ruby/Perl bindings that call libc chown()
 *
 * LIMITATIONS:
 *   - Go programs (buildah, podman) use raw syscalls, NOT libc.
 *     buildah COPY --chown is NOT intercepted. Use RUN chown instead.
 *   - musl libc (Alpine) may not support /etc/ld.so.preload in older
 *     versions. Shell shims at /usr/local/bin/chown cover this case.
 *   - Statically-linked binaries bypass LD_PRELOAD entirely.
 *
 * BUILD:   gcc -shared -fPIC -o fakechown.so fakechown.c -ldl
 * INJECT:  mounts.conf → /usr/local/lib/fakechown.so
 *          mounts.conf → /etc/ld.so.preload (contains path to .so)
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>

int chown(const char *pathname, uid_t owner, gid_t group) {
    int (*real)(const char *, uid_t, gid_t);
    real = dlsym(RTLD_NEXT, "chown");
    if (!real) { errno = 0; return 0; }
    int ret = real(pathname, owner, group);
    if (ret == -1 && (errno == EINVAL || errno == EPERM)) {
        errno = 0;
        return 0;
    }
    return ret;
}

int lchown(const char *pathname, uid_t owner, gid_t group) {
    int (*real)(const char *, uid_t, gid_t);
    real = dlsym(RTLD_NEXT, "lchown");
    if (!real) { errno = 0; return 0; }
    int ret = real(pathname, owner, group);
    if (ret == -1 && (errno == EINVAL || errno == EPERM)) {
        errno = 0;
        return 0;
    }
    return ret;
}

int fchown(int fd, uid_t owner, gid_t group) {
    int (*real)(int, uid_t, gid_t);
    real = dlsym(RTLD_NEXT, "fchown");
    if (!real) { errno = 0; return 0; }
    int ret = real(fd, owner, group);
    if (ret == -1 && (errno == EINVAL || errno == EPERM)) {
        errno = 0;
        return 0;
    }
    return ret;
}

int fchownat(int dirfd, const char *pathname, uid_t owner, gid_t group, int flags) {
    int (*real)(int, const char *, uid_t, gid_t, int);
    real = dlsym(RTLD_NEXT, "fchownat");
    if (!real) { errno = 0; return 0; }
    int ret = real(dirfd, pathname, owner, group, flags);
    if (ret == -1 && (errno == EINVAL || errno == EPERM)) {
        errno = 0;
        return 0;
    }
    return ret;
}
