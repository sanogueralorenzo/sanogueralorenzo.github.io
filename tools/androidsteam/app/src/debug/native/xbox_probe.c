#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/eventfd.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define CHECK(test) do { if (!(test)) { fprintf(stderr, "Xbox probe failed at line %d\n", __LINE__); return 1; } } while (0)
static int bit(const unsigned char *bits, int code) { return !!(bits[code / 8] & (1 << (code % 8))); }
int main(void) {
    setbuf(stdout, NULL);
    int fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
    CHECK(fd >= 0);
    struct input_id id = {};
    CHECK(ioctl(fd, EVIOCGID, &id) == 0 && id.bustype == BUS_USB && id.vendor == 0x045e && id.product == 0x028e);
    unsigned char bits[(KEY_MAX + 8) / 8] = {};
    CHECK(ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0 && bit(bits, BTN_A) && bit(bits, BTN_MODE));
    CHECK(ioctl(fd, EVIOCGKEY(sizeof(bits)), bits) >= 0 && bit(bits, BTN_A) && bit(bits, BTN_MODE));
    struct input_absinfo axis = {};
    CHECK(ioctl(fd, EVIOCGABS(ABS_X), &axis) == 0 && axis.value >= 16370 && axis.value <= 16400 && axis.maximum == 32767);
    struct input_event events[32];
    struct pollfd poller = {fd, POLLIN, 0};
    CHECK(poll(&poller, 1, 1000) == 1 && read(fd, events, sizeof(events)) > 0); // Late-open snapshot.
    puts("xbox-recognized-held");
    int released = 0;
    for (int attempt = 0; attempt < 100 && !released; attempt++) {
        CHECK(poll(&poller, 1, 100) >= 0);
        ssize_t count = read(fd, events, sizeof(events));
        if (count <= 0) continue;
        for (unsigned i = 0; i < count / sizeof(*events); i++)
            if (events[i].type == EV_KEY && events[i].code == BTN_A && events[i].value == 0) released = 1;
    }
    CHECK(released);
    CHECK(ioctl(fd, EVIOCGKEY(sizeof(bits)), bits) >= 0 && !bit(bits, BTN_A));
    close(fd);
    puts("xbox-released");

    // Steam Input's modern uinput path must publish a readable virtual pad.
    int ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    CHECK(ui >= 0);
    CHECK(ioctl(ui, UI_SET_EVBIT, EV_KEY) == 0 && ioctl(ui, UI_SET_KEYBIT, BTN_A) == 0 && ioctl(ui, UI_SET_KEYBIT, BTN_B) == 0);
    CHECK(ioctl(ui, UI_SET_EVBIT, EV_ABS) == 0 && ioctl(ui, UI_SET_ABSBIT, ABS_X) == 0 && ioctl(ui, UI_SET_ABSBIT, ABS_Y) == 0);
    struct uinput_setup setup = {};
    setup.id.bustype = BUS_USB; setup.id.vendor = 0x28de; setup.id.product = 0x11ff;
    strcpy(setup.name, "Steam Virtual Gamepad");
    CHECK(ioctl(ui, UI_DEV_SETUP, &setup) == 0 && ioctl(ui, UI_DEV_CREATE) == 0);
    int virtual = open("/dev/input/event16", O_RDONLY | O_NONBLOCK);
    CHECK(virtual >= 0 && ioctl(virtual, EVIOCGID, &id) == 0 && id.vendor == 0x28de && id.product == 0x11ff);
    struct input_event press[2] = {{.type = EV_KEY, .code = BTN_B, .value = 1}, {.type = EV_SYN, .code = SYN_REPORT}};
    CHECK(write(ui, press, sizeof(press)) == sizeof(press));
    CHECK(ioctl(virtual, EVIOCGKEY(sizeof(bits)), bits) >= 0 && bit(bits, BTN_B));
    close(virtual);
    CHECK(ioctl(ui, UI_DEV_DESTROY) == 0);
    close(ui);
    CHECK(access("/dev/input/event16", F_OK) != 0);
    puts("steam-input-uinput-recognized");

    // Libraries may close descriptors through a syscall, bypassing our close hook.
    // Reusing that number must never turn an ordinary file into a controller.
    fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
    CHECK(fd >= 0 && syscall(SYS_close, fd) == 0);
    int reused = open("/etc/hosts", O_RDONLY);
    CHECK(reused == fd);
    struct stat status = {};
    CHECK(fstat(reused, &status) == 0 && S_ISREG(status.st_mode));
    char byte;
    CHECK(read(reused, &byte, 1) == 1);
    close(reused);
    fd = open("/dev/input/event0", O_RDONLY | O_NONBLOCK);
    int pipefd[2];
    CHECK(fd >= 0 && pipe(pipefd) == 0 && dup2(pipefd[0], fd) == fd);
    CHECK(write(pipefd[1], "x", 1) == 1);
    poller = (struct pollfd){fd, POLLIN, 0};
    CHECK(poll(&poller, 1, 1000) == 1 && (poller.revents & POLLIN));
    CHECK(read(fd, &byte, 1) == 1 && byte == 'x');
    CHECK(fstat(fd, &status) == 0 && S_ISFIFO(status.st_mode));
    close(fd); close(pipefd[0]); close(pipefd[1]);

    ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    CHECK(ui >= 0 && syscall(SYS_close, ui) == 0);
    reused = open("/etc/hosts", O_RDONLY);
    CHECK(reused == ui && read(reused, &byte, 1) == 1);
    CHECK(ioctl(reused, UI_DEV_CREATE) == -1);
    close(reused);
    // All eventfds share an anonymous inode. A raw-close/reuse must not
    // swallow an unrelated wakeup as if it were a uinput event write.
    ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    CHECK(ui >= 0 && syscall(SYS_close, ui) == 0);
    reused = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    CHECK(reused == ui);
    uint64_t signal = 7, received = 0;
    CHECK(write(reused, &signal, sizeof(signal)) == sizeof(signal));
    poller = (struct pollfd){reused, POLLIN, 0};
    CHECK(poll(&poller, 1, 0) == 1 && (poller.revents & POLLIN));
    CHECK(read(reused, &received, sizeof(received)) == sizeof(received) && received == signal);
    CHECK(ioctl(reused, UI_DEV_CREATE) == -1);
    close(reused);
    puts("reused-descriptor-passes-through");
    return 0;
}
