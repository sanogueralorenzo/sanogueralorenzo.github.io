// SPDX-License-Identifier: GPL-3.0-only
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void query(unsigned port, int pid, unsigned peer) {
    char command[128], output[512] = {0}, expected[128];
    snprintf(command, sizeof(command), "/usr/bin/lsof -P -F upnR -i TCP@127.0.0.1:%u", port);
    FILE *pipe = popen(command, "r");
    assert(pipe);
    size_t size = fread(output, 1, sizeof(output) - 1, pipe);
    int status = pclose(pipe);
    if (!pid) { assert(status && !size); return; }
    assert(!status);
    snprintf(expected, sizeof(expected), "p%d\n", pid);
    assert(strstr(output, expected));
    snprintf(expected, sizeof(expected), "n127.0.0.1:%u", port);
    assert(strstr(output, expected));
    if (peer) { snprintf(expected, sizeof(expected), "->127.0.0.1:%u\n", peer); assert(strstr(output, expected)); }
}

int main(void) {
    int server = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    errno = EBUSY;
    assert(!bind(server, (struct sockaddr *)&address, sizeof(address)) && errno == EBUSY);
    assert(!listen(server, 1) && errno == EBUSY);
    socklen_t size = sizeof(address);
    assert(!getsockname(server, (struct sockaddr *)&address, &size));
    unsigned server_port = ntohs(address.sin_port);
    query(server_port, getpid(), 0);
    int ready[2], control[2];
    assert(!pipe(ready) && !pipe(control));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(ready[0]); close(control[1]); close(server);
        int client = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
        int result = connect(client, (struct sockaddr *)&address, sizeof(address));
        assert(!result || errno == EINPROGRESS);
        assert(!getsockname(client, (struct sockaddr *)&address, &size));
        unsigned port = ntohs(address.sin_port);
        assert(write(ready[1], &port, sizeof(port)) == sizeof(port));
        char signal;
        assert(read(control[0], &signal, 1) == 1);
        close(client);
        int replacement = open("/dev/null", O_RDONLY);
        assert(replacement == client);
        assert(write(ready[1], "c", 1) == 1);
        assert(read(control[0], &signal, 1) == 1);
        _exit(0);
    }
    close(ready[1]); close(control[0]);
    unsigned client_port;
    assert(read(ready[0], &client_port, sizeof(client_port)) == sizeof(client_port));
    int accepted = accept4(server, NULL, NULL, SOCK_CLOEXEC);
    assert(accepted >= 0);
    query(client_port, child, server_port);
    query(server_port, getpid(), client_port);
    int udp = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    address.sin_port = htons(client_port);
    assert(!bind(udp, (struct sockaddr *)&address, sizeof(address)));
    query(client_port, child, server_port);
    close(udp);
    assert(write(control[1], "c", 1) == 1);
    char signal;
    assert(read(ready[0], &signal, 1) == 1);
    query(client_port, 0, 0);
    close(accepted);
    query(server_port, getpid(), 0);
    close(server);
    query(server_port, 0, 0);
    assert(write(control[1], "x", 1) == 1);
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    puts("Live socket peers verified");
    return 0;
}
