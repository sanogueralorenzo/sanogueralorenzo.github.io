// X11 must support both the UTF-8 environment and Steam's C-locale fallback.
#include <dlfcn.h>
#include <locale.h>
#include <stdio.h>

int main(void) {
    void *library = dlopen("libX11.so.6", RTLD_NOW);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    int (*supports)(void) = dlsym(library, "XSupportsLocale");
    const char *locales[] = {"C.UTF-8", "C"};
    for (unsigned i = 0; i < sizeof(locales) / sizeof(locales[0]); ++i) {
        if (!supports || !setlocale(LC_ALL, locales[i]) || !supports()) {
            fprintf(stderr, "X11 does not support %s\n", locales[i]);
            return 1;
        }
    }
    puts("X11 locales verified");
    dlclose(library);
    return 0;
}
