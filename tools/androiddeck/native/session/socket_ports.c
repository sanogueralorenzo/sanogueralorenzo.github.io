/* SPDX-License-Identifier: GPL-3.0-only
 * Adapted from DroidDeck tools/linuxfs/preload/net.c at
 * 255c64551ec7d5a810da622d918eb88ffdccb231; see THIRD_PARTY.md.
 * Android hides /proc/net and sock_diag. Record only Steam's actual loopback
 * TCP sockets so its browser peer checks can still identify their owners.
 */
#define _GNU_SOURCE
#include "socket_ports.h"
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

static int (*real_bind)(int, const struct sockaddr *, socklen_t);
static int (*real_listen)(int, int);
static int (*real_connect)(int, const struct sockaddr *, socklen_t);
static int (*real_accept4)(int, struct sockaddr *, socklen_t *, int);

__attribute__((constructor)) static void resolve_sockets(void) {
    real_bind = dlsym(RTLD_NEXT, "bind");
    real_listen = dlsym(RTLD_NEXT, "listen");
    real_connect = dlsym(RTLD_NEXT, "connect");
    real_accept4 = dlsym(RTLD_NEXT, "accept4");
}

static unsigned loopback_port(const struct sockaddr_in *address, socklen_t size) {
    return size >= sizeof(*address) && address->sin_family == AF_INET &&
        address->sin_addr.s_addr == htonl(INADDR_LOOPBACK) ? ntohs(address->sin_port) : 0;
}

static void record_socket(int fd, unsigned requested_peer) {
    int saved_errno = errno, type;
    socklen_t size = sizeof(type);
    struct sockaddr_in local, remote;
    struct stat stat;
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &size) || type != SOCK_STREAM) goto done;
    size = sizeof(local);
    if (getsockname(fd, (struct sockaddr *)&local, &size)) goto done;
    unsigned port = loopback_port(&local, size);
    if (!port || fstat(fd, &stat)) goto done;
    size = sizeof(remote);
    unsigned peer = getpeername(fd, (struct sockaddr *)&remote, &size) == 0 ? loopback_port(&remote, size) : requested_peer;
    struct deck_socket_port entry = {getpid(), getppid(), getuid(), fd, port, peer, stat.st_ino};
    char directory[128], temporary[160], path[160];
    snprintf(directory, sizeof(directory), DECK_SOCKET_PORTS "/%u", port);
    if (mkdir(directory, 0700) && errno != EEXIST) goto done;
    snprintf(temporary, sizeof(temporary), "%s/.port-XXXXXX", directory);
    snprintf(path, sizeof(path), "%s/%d-%d", directory, entry.pid, fd);
    int out = mkostemp(temporary, O_CLOEXEC);
    if (out >= 0) {
        ssize_t written = write(out, &entry, sizeof(entry));
        close(out);
        if (written == sizeof(entry)) rename(temporary, path);
        unlink(temporary);
    }
done:
    errno = saved_errno;
}

int bind(int fd, const struct sockaddr *address, socklen_t size) {
    int result = real_bind(fd, address, size);
    if (!result) record_socket(fd, 0);
    return result;
}

int listen(int fd, int backlog) {
    int result = real_listen(fd, backlog);
    if (!result) record_socket(fd, 0);
    return result;
}

int connect(int fd, const struct sockaddr *address, socklen_t size) {
    int result = real_connect(fd, address, size);
    if (!result || errno == EINPROGRESS) record_socket(fd, loopback_port((const struct sockaddr_in *)address, size));
    return result;
}

int accept4(int fd, struct sockaddr *address, socklen_t *size, int flags) {
    int result = real_accept4(fd, address, size, flags);
    if (result >= 0) record_socket(result, 0);
    return result;
}

int accept(int fd, struct sockaddr *address, socklen_t *size) {
    return accept4(fd, address, size, 0);
}
