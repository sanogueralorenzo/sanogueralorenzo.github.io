#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: build-android.sh <jniLibs-output-dir> <ndk-version>" >&2
  exit 2
fi

output_dir="$1"
ndk_version="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_dir="$(cd "${script_dir}/.." && pwd)"
repo_voice_dir="$(cd "${engine_dir}/.." && pwd)"
cargo_runner="${script_dir}/run-cargo.sh"

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "${sdk_dir}" ] && [ -f "${repo_voice_dir}/android/local.properties" ]; then
  sdk_dir="$(sed -n 's/^sdk.dir=//p' "${repo_voice_dir}/android/local.properties" | tail -1)"
fi
if [ -z "${sdk_dir}" ] || [ ! -d "${sdk_dir}" ]; then
  echo "Android SDK not found. Set ANDROID_HOME or android/local.properties sdk.dir." >&2
  exit 1
fi

ndk_dir="${sdk_dir}/ndk/${ndk_version}"
if [ ! -d "${ndk_dir}" ]; then
  echo "Android NDK ${ndk_version} not found at ${ndk_dir}. Install that exact version with Android SDK Manager." >&2
  exit 1
fi

host_tag="darwin-x86_64"
if [ "$(uname -s)" = "Linux" ]; then
  host_tag="linux-x86_64"
fi
if [ "$(uname -m)" = "arm64" ] && [ -d "${ndk_dir}/toolchains/llvm/prebuilt/darwin-arm64" ]; then
  host_tag="darwin-arm64"
fi

toolchain_bin="${ndk_dir}/toolchains/llvm/prebuilt/${host_tag}/bin"
api="${ANDROID_API_LEVEL:-24}"

build_target() {
  local rust_target="$1"
  local abi="$2"
  local linker_prefix="$3"
  local env_name
  env_name="$(echo "${rust_target}" | tr '[:lower:]-' '[:upper:]_')"

  (
    cd "${engine_dir}"
    rustup target add "${rust_target}" >/dev/null
    env "CARGO_TARGET_${env_name}_LINKER=${toolchain_bin}/${linker_prefix}${api}-clang" \
      "${cargo_runner}" build --release --target "${rust_target}"
  )

  mkdir -p "${output_dir}/${abi}"
  cp "${engine_dir}/target/${rust_target}/release/libvoice_engine.so" "${output_dir}/${abi}/libvoice_engine.so"
}

build_target "aarch64-linux-android" "arm64-v8a" "aarch64-linux-android"
build_target "armv7-linux-androideabi" "armeabi-v7a" "armv7a-linux-androideabi"
build_target "i686-linux-android" "x86" "i686-linux-android"
build_target "x86_64-linux-android" "x86_64" "x86_64-linux-android"
