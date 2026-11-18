/* Exercises Wine-only discovery and Steam Input hot-removal through the real preload. */
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    void *(*device_new)(void *, const char *) = dlsym(RTLD_DEFAULT, "udev_device_new_from_syspath");
    const char *(*devnode)(void *) = dlsym(RTLD_DEFAULT, "udev_device_get_devnode");
    const char *(*sysattr)(void *, const char *) = dlsym(RTLD_DEFAULT, "udev_device_get_sysattr_value");
    const char *(*property)(void *, const char *) = dlsym(RTLD_DEFAULT, "udev_device_get_property_value");
    void *(*unref)(void *) = dlsym(RTLD_DEFAULT, "udev_device_unref");
    assert(device_new && devnode && sysattr && property && unref);
    char *ordinary = realpath("/usr", NULL);
    assert(ordinary && strcmp(ordinary, "/usr") == 0); free(ordinary);
    char *path = realpath("/sys/class/input/event0", NULL);
#ifndef WINE_CALLER
    assert(!path || !strstr(path, "/androidsteam")); free(path);
    assert(!device_new(NULL, "/sys/devices/virtual/input/androidsteam0"));
    puts("udev-other-callers-pass-through");
#else
    assert(path && strcmp(path, "/sys/devices/virtual/input/androidsteam0") == 0);
    void *physical = device_new(NULL, path); free(path);
    assert(physical && strcmp(devnode(physical), "/dev/input/event0") == 0);
    assert(strcmp(property(physical, "ID_INPUT_JOYSTICK"), "1") == 0);
    assert(strstr(sysattr(physical, "uevent"), "PRODUCT=6/28de/11ff/110"));
    const char *metadata = "/run/androidsteam/input/.uinput-event16.uevent";
    FILE *file = fopen(metadata, "w"); assert(file);
    assert(fputs("PRODUCT=6/28de/11ff/110\nNAME=\"Steam Input Gamepad\"\n", file) >= 0);
    assert(fclose(file) == 0);
    path = realpath("/sys/class/input/event0", NULL); assert(path); free(path);
    assert(strstr(sysattr(physical, "uevent"), "PRODUCT=3/45e/28e/110"));
    path = realpath("/sys/class/input/event16", NULL); assert(path);
    void *virtual = device_new(NULL, path); free(path);
    assert(virtual && strcmp(devnode(virtual), "/dev/input/event16") == 0);
    assert(strstr(sysattr(virtual, "uevent"), "Steam Input Gamepad"));
    assert(unlink(metadata) == 0);
    path = realpath("/sys/class/input/event16", NULL);
    assert(!path || !strstr(path, "/androidsteam")); free(path);
    /* Existing Wine references must remain safe after Steam removes its virtual device. */
    assert(unref(virtual) == NULL);
    path = realpath("/sys/class/input/event0", NULL); assert(path); free(path);
    assert(strstr(sysattr(physical, "uevent"), "PRODUCT=6/28de/11ff/110"));
    assert(unref(physical) == NULL);
    puts("wine-controller-discovery-and-hot-removal");
#endif
    return 0;
}
