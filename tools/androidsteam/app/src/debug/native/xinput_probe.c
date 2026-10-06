/* Minimal Windows ABI probe; no CRT, SDK, game payload or runtime dependency is bundled. */
typedef unsigned int DWORD;
typedef unsigned short WORD;
typedef unsigned char BYTE;
typedef short SHORT;
typedef struct { WORD buttons; BYTE leftTrigger, rightTrigger; SHORT leftX, leftY, rightX, rightY; } GAMEPAD;
typedef struct { DWORD packet; GAMEPAD gamepad; } STATE;
__declspec(dllimport) DWORD XInputGetState(DWORD, STATE *);
__declspec(dllimport) void *GetStdHandle(DWORD);
__declspec(dllimport) int WriteFile(void *, const void *, DWORD, DWORD *, void *);
__declspec(dllimport) void Sleep(DWORD);
__declspec(dllimport) void ExitProcess(DWORD);
static void emit(const char *text, DWORD length) { DWORD written; WriteFile(GetStdHandle((DWORD)-11), text, length, &written, 0); }
#define EMIT(text) emit(text "\n", sizeof(text "\n") - 1)
void entry(void) {
    int connected = 0, held = 0;
    for (int attempt = 0; attempt < 400; attempt++) {
        STATE state;
        for (DWORD index = 0; index < 4; index++) {
            if (XInputGetState(index, &state) != 0) continue;
            if (!connected) { EMIT("xinput-connected"); connected = 1; }
            if (!held && (state.gamepad.buttons & 0x1000) && state.gamepad.leftX > 12000) {
                EMIT("xinput-A-and-left-stick"); held = 1;
            } else if (held && state.gamepad.buttons == 0 && state.gamepad.leftX > -1000 && state.gamepad.leftX < 1000) {
                EMIT("xinput-released"); ExitProcess(0);
            }
        }
        Sleep(50);
    }
    EMIT("xinput-timeout"); ExitProcess(1);
}
