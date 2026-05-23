#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: build-android.sh <jniLibs-output-dir>" >&2
  exit 2
fi

output_dir="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_dir="$(cd "${script_dir}/.." && pwd)"
repo_voice_dir="$(cd "${engine_dir}/.." && pwd)"

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "${sdk_dir}" ] && [ -f "${repo_voice_dir}/android/local.properties" ]; then
  sdk_dir="$(sed -n 's/^sdk.dir=//p' "${repo_voice_dir}/android/local.properties" | tail -1)"
fi
if [ -z "${sdk_dir}" ] || [ ! -d "${sdk_dir}" ]; then
  echo "Android SDK not found. Set ANDROID_HOME or android/local.properties sdk.dir." >&2
  exit 1
fi

ndk_dir="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "${ndk_dir}" ]; then
  ndk_dir="$(find "${sdk_dir}/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ -z "${ndk_dir}" ] || [ ! -d "${ndk_dir}" ]; then
  echo "Android NDK not found under ${sdk_dir}/ndk." >&2
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

  rustup target add "${rust_target}" >/dev/null
  env "CARGO_TARGET_${env_name}_LINKER=${toolchain_bin}/${linker_prefix}${api}-clang" \
    cargo build --manifest-path "${engine_dir}/Cargo.toml" --release --target "${rust_target}"

  mkdir -p "${output_dir}/${abi}"
  cp "${engine_dir}/target/${rust_target}/release/libvoice_engine.so" "${output_dir}/${abi}/libvoice_engine.so"
}

build_target "aarch64-linux-android" "arm64-v8a" "aarch64-linux-android"
build_target "armv7-linux-androideabi" "armeabi-v7a" "armv7a-linux-androideabi"
build_target "i686-linux-android" "x86" "i686-linux-android"
build_target "x86_64-linux-android" "x86_64" "x86_64-linux-android"

