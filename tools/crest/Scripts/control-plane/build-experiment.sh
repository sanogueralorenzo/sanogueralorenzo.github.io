#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ $# -ne 1 || "$1" != /* || "$1" != *.app || -e "$1" ]]; then
    echo "Usage: $0 /absolute/new/path/CrestNativeCore.app" >&2
    exit 2
fi
output_app="$1"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/crest-control-plane.XXXXXX")"
cleanup() { if [[ -d "$build_root" ]]; then /usr/bin/trash "$build_root"; fi; }
trap cleanup EXIT INT TERM HUP

cd "$repo_root/CrestCore"
dotnet test tests/CrestCore.Tests --nologo
dotnet publish src/CrestCore.Native -c Release -r osx-arm64 -o "$build_root/core" --nologo
cd "$repo_root"
clang -std=c11 -Wall -Wextra -Werror -I CrestContracts/include \
    CrestContracts/tests/native_abi.c "$build_root/core/CrestCore.Native.dylib" \
    -Wl,-rpath,"$build_root/core" -o "$build_root/native-abi"
"$build_root/native-abi"
clang++ -std=c++20 -Wall -Wextra -Werror -Wconversion -I CrestContracts/include \
    CrestContracts/tests/engine_abi.cc "$build_root/core/CrestCore.Native.dylib" \
    -Wl,-rpath,"$build_root/core" -o "$build_root/engine-abi"
"$build_root/engine-abi"
xcodebuild -project Crest.xcodeproj -scheme CrestNativeCore -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$build_root/DerivedData" \
    CREST_CORE_LIBRARY_DIR="$build_root/core" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
mkdir -p "$(dirname "$output_app")"
ditto "$build_root/DerivedData/Build/Products/Debug/CrestNativeCore.app" "$output_app"
codesign --verify --deep --strict "$output_app"
echo "Built $output_app"
