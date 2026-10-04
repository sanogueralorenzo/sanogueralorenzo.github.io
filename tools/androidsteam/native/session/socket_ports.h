// SPDX-License-Identifier: GPL-3.0-only
#ifndef DECK_SOCKET_PORTS_H
#define DECK_SOCKET_PORTS_H

#define DECK_SOCKET_PORTS "/run/androidsteam/ports"

// Private session records; the peer query must verify fd/inode against /proc.
struct deck_socket_port {
    int pid, parent, uid, fd;
    unsigned port, peer;
    unsigned long inode;
};

#endif
