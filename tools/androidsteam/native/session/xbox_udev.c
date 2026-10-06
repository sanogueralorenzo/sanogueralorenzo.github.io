/*
 * Adapted from DroidDeck 05608ac4d4da33cfebcc0d6783064ec04ac75aee, tools/linuxfs/preload/inputudev.c.
 * Ported from WinNative (maxjivi05, feature/wayland-gamescope, 2026-09-18/19), GPL-3.0, with names
 * changed to this project's. The reasoning below is the original author's.
 *
 * The session's controllers, described to libudev's callers.
 *
 * The pads are evdev nodes the app backs with its own input rings, bound over /dev/input. Wine's
 * HID bus finds them there, but it identifies a node by resolving /sys/class/input/<name> and
 * asking libudev about the result: on Android that resolves to whatever real input device the
 * host numbered the same, whose device node libudev cannot read, so every pad is discarded before
 * its identity is ever looked at. The fallback is Wine's SDL bus, and SDL enumerates through udev
 * too, over a netlink socket the app sandbox refuses. A game was left with no controller at all
 * while the Steam client, which reads the nodes itself, had one.
 *
 * So the pads are described here instead: the resolved path is answered for the session's own
 * nodes, and libudev's accessors answer for that path from what the app already knows. They carry
 * the identity of a Steam Input pad, which Wine's own bus keeps rather than handing on to SDL.
 *
 * Only Wine's device host is answered, and only for the session's own nodes: the Steam client
 * enumerates the same nodes for itself and would take a pad wearing Steam Input's identity for one
 * of its own and ignore it. Every other caller, path and device object goes straight through.
 *
 * With libxbox-evdev's /dev/uinput stand-in (FAKE_EVDEV_UINPUT=1) Steam Input's own virtual pads
 * exist too, as event16 and up, and those are what Wine is meant to read: each is described with
 * the identity the client gave it, from the .uevent file libxbox-evdev writes beside the node.
 * While one exists the app's pads are described as what they are, an Xbox 360 controller, which
 * Wine's HID bus leaves alone - the game reads Steam Input's output, not the pad under it, as on
 * a Steam Deck. With none (Steam Input off for the game) they keep the virtual identity, so the
 * game still has a controller.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysmacros.h>
#include <sys/types.h>

/* One session-owned Xbox ring; Steam Input creates virtual pads from UINPUT_BASE onward. */
#define RING_MAX 1
#define UINPUT_BASE 16
#define PAD_MAX 64
#define EVENT_MINOR_BASE 64

/* BUS_VIRTUAL, and the identity Steam Input gives the gamepad it presents to a game. */
#define PAD_UEVENT_FORMAT                                                                          \
  "PRODUCT=6/28de/11ff/110\n"                                                                      \
  "NAME=\"Generic HID Gamepad %d\"\n"                                                              \
  "PHYS=\"usb-fakeinput/input%d\"\n"

/* The identity libxbox-evdev gives the pad itself (fixed Xbox 360 identity). */
#define PAD_PHYSICAL_UEVENT_FORMAT                                                                 \
  "PRODUCT=3/45e/28e/110\n"                                                                        \
  "NAME=\"Xbox 360 Controller (%d)\"\n"                                                            \
  "PHYS=\"usb-fakeinput/input%d\"\n"

struct pad {
  char syspath[64];
  char devnode[32];
  char sysname[16];
  char uevent[256];
  dev_t devnum;
};

static struct pad pads[PAD_MAX];
static int pad_count;
static pthread_mutex_t virtual_lock = PTHREAD_MUTEX_INITIALIZER;

/*
 * The slots the app published rings for, named in FAKE_EVDEV_MEMFD_PATHS as "<slot>=<path>"
 * separated by semicolons. Without it the process has no pads of the session's and every call
 * here is a passthrough.
 */
static void discover_pads(void) {
  const char *spec = getenv("FAKE_EVDEV_MEMFD_PATHS");
  const char *entry;

  if (spec == NULL) return;
  for (entry = spec; *entry != '\0';) {
    char *end;
    long slot = strtol(entry, &end, 10);

    if (end != entry && *end == '=' && slot >= 0 && slot < RING_MAX) {
      struct pad *pad = &pads[slot];

      if (pad->devnode[0] == '\0') {
        snprintf(pad->sysname, sizeof(pad->sysname), "event%ld", slot);
        snprintf(pad->syspath, sizeof(pad->syspath), "/sys/devices/virtual/input/androidsteam%ld",
                 slot);
        snprintf(pad->devnode, sizeof(pad->devnode), "/dev/input/event%ld", slot);
        snprintf(pad->uevent, sizeof(pad->uevent), PAD_UEVENT_FORMAT, (int)slot, (int)slot);
        pad->devnum = makedev(13, EVENT_MINOR_BASE + (unsigned int)slot);
        if (slot >= pad_count) pad_count = (int)slot + 1;
      }
    }
    entry = strchr(entry, ';');
    if (entry == NULL) break;
    entry++;
  }
}

static void ensure_pads(void) {
  static pthread_once_t once = PTHREAD_ONCE_INIT;
  pthread_once(&once, discover_pads);
}

static int uinput_enabled(void) {
  const char *enabled = getenv("FAKE_EVDEV_UINPUT");
  return enabled != NULL && atoi(enabled) != 0;
}

/* Reads the .uevent libxbox-evdev wrote for virtual pad <node> into buf; 0 when there is none. */
static int read_virtual_uevent(int node, char *buf, size_t size) {
  const char *dir = getenv("FAKE_EVDEV_DIR");
  char path[PATH_MAX];
  FILE *file;
  size_t length;

  if (dir == NULL) return 0;
  snprintf(path, sizeof(path), "%s/.uinput-event%d.uevent", dir, node);
  if ((file = fopen(path, "re")) == NULL) return 0;
  length = fread(buf, 1, size - 1, file);
  fclose(file);
  buf[length] = '\0';
  return length > 0;
}

static int any_virtual_pad(void) {
  char uevent[256];
  int node;

  for (node = UINPUT_BASE; node < PAD_MAX; node++)
    if (read_virtual_uevent(node, uevent, sizeof(uevent))) return 1;
  return 0;
}

/*
 * Brings the entry for event<node> up to date before Wine resolves it: a virtual pad comes and
 * goes with the client, and the app's pads change identity with it.
 */
static void refresh_pad(int node) {
  struct pad *pad;

  if (node < 0 || node >= PAD_MAX) return;
  pad = &pads[node];
  pthread_mutex_lock(&virtual_lock);
  if (node >= UINPUT_BASE) {
    char uevent[sizeof(pad->uevent)];

    if (read_virtual_uevent(node, uevent, sizeof(uevent))) {
      snprintf(pad->sysname, sizeof(pad->sysname), "event%d", node);
      snprintf(pad->syspath, sizeof(pad->syspath), "/sys/devices/virtual/input/androidsteam%d", node);
      memcpy(pad->uevent, uevent, sizeof(uevent));
      pad->devnum = makedev(13, EVENT_MINOR_BASE + (unsigned int)node);
      snprintf(pad->devnode, sizeof(pad->devnode), "/dev/input/event%d", node);
      if (node >= pad_count) pad_count = node + 1;
    } else {
      pad->devnode[0] = '\0';
    }
  } else if (pad->devnode[0] != '\0' && uinput_enabled()) {
    snprintf(pad->uevent, sizeof(pad->uevent),
             any_virtual_pad() ? PAD_PHYSICAL_UEVENT_FORMAT : PAD_UEVENT_FORMAT, node, node);
  }
  pthread_mutex_unlock(&virtual_lock);
}

/* The pad a synthetic syspath names, or NULL when the path is not one of ours. */
static struct pad *pad_for_syspath(const char *syspath) {
  int i;

  if (syspath == NULL) return NULL;
  ensure_pads();
  for (i = 0; i < pad_count; i++) {
    if (pads[i].devnode[0] != '\0' && strcmp(pads[i].syspath, syspath) == 0) return &pads[i];
  }
  return NULL;
}

/* A device object is ours exactly when it is one of the pads. */
static struct pad *pad_for_device(void *device) {
  int i;

  if (device == NULL) return NULL;
  ensure_pads();
  for (i = 0; i < pad_count; i++) {
    /* A removed virtual pad may still be referenced by Wine during teardown. */
    if (&pads[i] == device) return &pads[i];
  }
  return NULL;
}

/* The pad /sys/class/input/<name> stands for, or NULL when the path names something else. */
static struct pad *pad_for_syslink(const char *path) {
  static const char prefix[] = "/sys/class/input/";
  const char *name;
  int i;

  if (path == NULL || strncmp(path, prefix, sizeof(prefix) - 1) != 0) return NULL;
  name = path + sizeof(prefix) - 1;
  ensure_pads();
  if (strncmp(name, "event", 5) == 0 && name[5] >= '0' && name[5] <= '9') refresh_pad(atoi(name + 5));
  for (i = 0; i < pad_count; i++) {
    if (pads[i].devnode[0] != '\0' && strcmp(pads[i].sysname, name) == 0) return &pads[i];
  }
  return NULL;
}

static void *next_symbol(const char *name) { return dlsym(RTLD_NEXT, name); }

/* Wine reaches libudev from its HID bus driver, which is the only caller these pads are for. */
static int caller_is_winebus(void *caller) {
  Dl_info info;

  if (dladdr(caller, &info) == 0 || info.dli_fname == NULL) return 0;
  return strstr(info.dli_fname, "winebus.so") != NULL;
}

char *realpath(const char *path, char *resolved) {
  static char *(*real_realpath)(const char *, char *);
  void *caller = __builtin_return_address(0);
  struct pad *pad = caller_is_winebus(caller) ? pad_for_syslink(path) : NULL;

  if (pad != NULL) {
    if (resolved == NULL) return strdup(pad->syspath);
    /* PATH_MAX is what the caller promises when it passes a buffer. */
    memcpy(resolved, pad->syspath, strlen(pad->syspath) + 1);
    return resolved;
  }
  if (real_realpath == NULL) real_realpath = next_symbol("realpath");
  if (real_realpath == NULL) return NULL;
  return real_realpath(path, resolved);
}

void *udev_device_new_from_syspath(void *udev, const char *syspath) {
  static void *(*real_new)(void *, const char *);
  void *caller = __builtin_return_address(0);
  struct pad *pad = caller_is_winebus(caller) ? pad_for_syspath(syspath) : NULL;

  if (pad != NULL) return pad;
  if (real_new == NULL) real_new = next_symbol("udev_device_new_from_syspath");
  if (real_new == NULL) return NULL;
  return real_new(udev, syspath);
}

void *udev_device_ref(void *device) {
  static void *(*real_ref)(void *);

  if (pad_for_device(device) != NULL) return device;
  if (real_ref == NULL) real_ref = next_symbol("udev_device_ref");
  if (real_ref == NULL) return NULL;
  return real_ref(device);
}

void *udev_device_unref(void *device) {
  static void *(*real_unref)(void *);

  if (pad_for_device(device) != NULL) return NULL;
  if (real_unref == NULL) real_unref = next_symbol("udev_device_unref");
  if (real_unref == NULL) return NULL;
  return real_unref(device);
}

const char *udev_device_get_devnode(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return pad->devnode;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_devnode");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

const char *udev_device_get_syspath(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return pad->syspath;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_syspath");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

const char *udev_device_get_sysname(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return pad->sysname;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_sysname");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

const char *udev_device_get_subsystem(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return "input";
  if (real_get == NULL) real_get = next_symbol("udev_device_get_subsystem");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

const char *udev_device_get_devtype(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return NULL;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_devtype");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

const char *udev_device_get_action(void *device) {
  static const char *(*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return NULL;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_action");
  if (real_get == NULL) return NULL;
  return real_get(device);
}

dev_t udev_device_get_devnum(void *device) {
  static dev_t (*real_get)(void *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return pad->devnum;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_devnum");
  if (real_get == NULL) return makedev(0, 0);
  return real_get(device);
}

/*
 * A pad has no bus behind it, so it stands in for its own input device and has no other parent.
 * The reference is a borrowed one either way.
 */
void *udev_device_get_parent_with_subsystem_devtype(void *device, const char *subsystem,
                                                    const char *devtype) {
  static void *(*real_get)(void *, const char *, const char *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) {
    if (subsystem != NULL && strcmp(subsystem, "input") == 0 && devtype == NULL) return pad;
    return NULL;
  }
  if (real_get == NULL) real_get = next_symbol("udev_device_get_parent_with_subsystem_devtype");
  if (real_get == NULL) return NULL;
  return real_get(device, subsystem, devtype);
}

const char *udev_device_get_sysattr_value(void *device, const char *attr) {
  static const char *(*real_get)(void *, const char *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return attr != NULL && strcmp(attr, "uevent") == 0 ? pad->uevent : NULL;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_sysattr_value");
  if (real_get == NULL) return NULL;
  return real_get(device, attr);
}

const char *udev_device_get_property_value(void *device, const char *key) {
  static const char *(*real_get)(void *, const char *);
  struct pad *pad = pad_for_device(device);

  if (pad != NULL) return key != NULL && strcmp(key, "ID_INPUT_JOYSTICK") == 0 ? "1" : NULL;
  if (real_get == NULL) real_get = next_symbol("udev_device_get_property_value");
  if (real_get == NULL) return NULL;
  return real_get(device, key);
}
