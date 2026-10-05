/* Private CEF command/response pipes; credentials never enter process arguments. */
#define _GNU_SOURCE
#include <fcntl.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int attach(const char *path, int target) {
    int fd = open(path, O_RDWR | O_NOFOLLOW);
    struct stat info;
    if (fd < 0) return -1;
    if (fstat(fd, &info) || !S_ISFIFO(info.st_mode)) { close(fd); return -1; }
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
    int argc = 0;
    while (argv[argc]) {
        if (!strncmp(argv[argc], "--type=", 7)) return original(path, argv);
        if (++argc > 2048) { errno = E2BIG; return -1; }
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
        free(arguments); return -1;
    }
    arguments[count++] = "--remote-debugging-pipe";
    int result = original(path, arguments);
    int saved_errno = errno;
    free(arguments);
    errno = saved_errno;
    return result;
}
