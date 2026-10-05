/* Debug-only proof of CEF's private CDP pipe; never accepts credentials. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void phase(const char *value) {
    int fd = open("/run/androidsteam/ui-probe-status", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    if (fd >= 0) { write(fd, value, strlen(value)); close(fd); }
}

static int attach(const char *path, int target) {
    int fd = open(path, O_RDWR | O_NOFOLLOW);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) || !S_ISFIFO(info.st_mode)) return -1;
    if (fd != target) {
        if (dup2(fd, target) < 0) { close(fd); return -1; }
        close(fd);
    }
    return fcntl(target, F_SETFD, 0);
}

int execvp(const char *path, char *const argv[]) {
    int (*original)(const char *, char *const[]) = dlsym(RTLD_NEXT, "execvp");
    const char *name = strrchr(path, '/');
    name = name ? name + 1 : path;
    if (strcmp(name, "steamwebhelper")) return original(path, argv);
    phase("entered\n");
    int argc = 0;
    while (argv[argc]) {
        if (!strncmp(argv[argc], "--type=", 7)) return original(path, argv);
        if (++argc > 2048) return -1;
    }
    char **arguments = calloc((size_t)argc + 2, sizeof(char *));
    if (!arguments) return -1;
    int count = 0;
    for (int i = 0; i < argc; i++) {
        if (!strncmp(argv[i], "--remote-debugging-port=", 24)) continue;
        if (!strcmp(argv[i], "--remote-debugging-port")) { i++; continue; }
        arguments[count++] = argv[i];
    }
    if (attach("/run/androidsteam/ui-command", 3) || attach("/run/androidsteam/ui-response", 4)) {
        phase("pipe-failed\n"); free(arguments); return -1;
    }
    phase("pipe-attached\n");
    arguments[count++] = "--remote-debugging-pipe";
    int result = original(path, arguments);
    phase("exec-failed\n");
    free(arguments);
    return result;
}
