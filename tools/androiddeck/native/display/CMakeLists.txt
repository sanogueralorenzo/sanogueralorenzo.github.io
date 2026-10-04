cmake_minimum_required(VERSION 3.22)
project(AndroidDeckDisplay C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT DECK_DEPS)
    message(FATAL_ERROR "DECK_DEPS must point to verified Wayland/libffi sources")
endif()
set(WAYLAND "${DECK_DEPS}/wayland")
set(GENERATED "${DECK_DEPS}/generated")
add_library(wayland STATIC
    ${WAYLAND}/src/wayland-server.c ${WAYLAND}/src/wayland-shm.c
    ${WAYLAND}/src/event-loop.c ${WAYLAND}/src/connection.c
    ${WAYLAND}/src/wayland-os.c ${WAYLAND}/src/wayland-util.c
    ${GENERATED}/wayland-protocol.c)
target_include_directories(wayland PUBLIC ${WAYLAND}/src ${GENERATED}
    PRIVATE ${WAYLAND} ${DECK_DEPS}/ffi-install/include)
target_compile_definitions(wayland PRIVATE _POSIX_C_SOURCE=200809L)
target_link_libraries(wayland PUBLIC ${DECK_DEPS}/ffi-install/lib/libffi.a m)
add_library(deck-display SHARED src/server.c src/surface.c src/shell.c src/presentation.c src/jni.c
    ${GENERATED}/xdg-shell-protocol.c)
target_compile_options(deck-display PRIVATE -Wall -Wextra -Wno-unused-parameter)
target_compile_definitions(deck-display PRIVATE _GNU_SOURCE)
target_link_libraries(deck-display PRIVATE wayland android log)
