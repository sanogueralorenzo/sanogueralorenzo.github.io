cmake_minimum_required(VERSION 3.22)
project(AndroidDeckDisplay C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT DECK_DEPS)
    message(FATAL_ERROR "DECK_DEPS must point to verified Wayland/libffi sources")
endif()
set(WAYLAND "${DECK_DEPS}/wayland")
set(GENERATED "${DECK_DEPS}/generated")
add_subdirectory("${DECK_DEPS}/adrenotools" adrenotools)
add_library(wayland STATIC
    ${WAYLAND}/src/wayland-server.c ${WAYLAND}/src/wayland-shm.c
    ${WAYLAND}/src/event-loop.c ${WAYLAND}/src/connection.c
    ${WAYLAND}/src/wayland-os.c ${WAYLAND}/src/wayland-util.c
    ${GENERATED}/wayland-protocol.c)
target_include_directories(wayland PUBLIC ${WAYLAND}/src ${GENERATED}
    PRIVATE ${WAYLAND} ${DECK_DEPS}/ffi-install/include)
target_compile_definitions(wayland PRIVATE _POSIX_C_SOURCE=200809L)
target_link_libraries(wayland PUBLIC ${DECK_DEPS}/ffi-install/lib/libffi.a m)
# Embed the generated, self-contained upstream US keymap without a runtime compiler.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/input/us.xkb")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/input/us.xkb" KEYMAP)
string(REPLACE "\\" "\\\\" KEYMAP "${KEYMAP}")
string(REPLACE "\"" "\\\"" KEYMAP "${KEYMAP}")
string(REPLACE "\n" "\\n\"\n\"" KEYMAP "${KEYMAP}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/keymap.h" "static const char deck_keymap[] = \"${KEYMAP}\";\n")
add_library(deck-display SHARED src/input.c src/server.c src/surface.c src/shell.c src/presentation.c src/jni.c
    src/gpu.c src/gpu_surface.c src/gpu_import.c src/gpu_present.c
    src/dmabuf.c src/explicit_sync.c src/feedback.c
    ${GENERATED}/xdg-shell-protocol.c ${GENERATED}/linux-dmabuf-protocol.c ${GENERATED}/explicit-sync-protocol.c
    ${GENERATED}/presentation-time-protocol.c)
target_include_directories(deck-display PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_options(deck-display PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_compile_definitions(deck-display PRIVATE _GNU_SOURCE)
target_link_libraries(deck-display PRIVATE wayland adrenotools android log dl)
