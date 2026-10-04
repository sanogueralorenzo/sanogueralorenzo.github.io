/* SPDX-License-Identifier: GPL-3.0-only
 * Steam's lsof -P -F upnR -i TCP@127.0.0.1:port peer query.
 * Adapted from DroidDeck net.c at 255c64551ec7d5a810da622d918eb88ffdccb231.
 * Report a registry entry only while that process still owns that socket.
 */
#include "socket_ports.h"
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int report(int directory, const char *name, unsigned port) {
    int fd = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return 0;
    struct deck_socket_port entry;
    ssize_t size = read(fd, &entry, sizeof(entry));
    close(fd);
    if (size != sizeof(entry) || entry.port != port || entry.pid <= 0 || entry.fd < 0) return 0;
    char path[128], target[128], expected[64];
    snprintf(path, sizeof(path), "/proc/%d/fd/%d", entry.pid, entry.fd);
    size = readlink(path, target, sizeof(target) - 1);
    if (size <= 0) return 0;
    target[size] = 0;
    snprintf(expected, sizeof(expected), "socket:[%lu]", entry.inode);
    if (strcmp(target, expected)) return 0;
    printf("p%d\nR%d\nu%d\nn127.0.0.1:%u", entry.pid, entry.parent, entry.uid, port);
    if (entry.peer) printf("->127.0.0.1:%u", entry.peer);
    puts("");
    return 1;
}

int main(int argc, char **argv) {
    unsigned port = 0;
    for (int i = 1; i + 1 < argc; i++) {
        if (strcmp(argv[i], "-i")) continue;
        const char *query = argv[i + 1], *prefix = "TCP@127.0.0.1:";
        if (strncmp(query, prefix, strlen(prefix))) return 1;
        char *end;
        unsigned long value = strtoul(query + strlen(prefix), &end, 10);
        if (*end || value == 0 || value > 65535) return 1;
        port = value;
    }
    if (!port) return 1;
    char path[128];
    snprintf(path, sizeof(path), DECK_SOCKET_PORTS "/%u", port);
    DIR *directory = opendir(path);
    if (!directory) return 1;
    int reported = 0;
    struct dirent *entry;
    while ((entry = readdir(directory))) {
        if (entry->d_name[0] != '.') reported += report(dirfd(directory), entry->d_name, port);
    }
    closedir(directory);
    return !reported || ferror(stdout) ? 1 : 0;
}
