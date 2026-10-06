#!/usr/bin/env bash
set -euo pipefail
: "${NDK:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; Linux) HOST=linux-x86_64 ;; *) exit 1 ;; esac
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/kernel32.def" <<IMPORTS
LIBRARY kernel32.dll
EXPORTS
GetStdHandle
WriteFile
Sleep
ExitProcess
IMPORTS
cat > "$WORK/xinput.def" <<IMPORTS
LIBRARY xinput1_3.dll
EXPORTS
XInputGetState
IMPORTS
for library in kernel32 xinput; do
    "$TOOLS/llvm-dlltool" -m i386:x86-64 -d "$WORK/$library.def" -l "$WORK/$library.lib"
done
"$TOOLS/clang" --target=x86_64-windows-msvc -O2 -fno-stack-protector -c "$HERE/xinput_probe.c" -o "$WORK/probe.obj"
"$TOOLS/lld-link" /machine:x64 /entry:entry /subsystem:console /nodefaultlib /timestamp:0 \
    "$WORK/probe.obj" "$WORK/kernel32.lib" "$WORK/xinput.lib" /out:"$OUT/xinput-probe-x64.exe"
