#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
engine_dir="$(cd "${script_dir}/.." && pwd)"

if ! command -v rustup >/dev/null 2>&1; then
  echo "rustup is required. Install it from https://rustup.rs/." >&2
  exit 1
fi

cd "${engine_dir}"

active_toolchain="$(rustup show active-toolchain | awk 'NR == 1 { print $1 }')"
if [ -z "${active_toolchain}" ]; then
  echo "Unable to resolve the Rust toolchain from ${engine_dir}/rust-toolchain.toml." >&2
  exit 1
fi

cargo_bin="$(rustup which --toolchain "${active_toolchain}" cargo)"
rustc_bin="$(rustup which --toolchain "${active_toolchain}" rustc)"
rustdoc_bin="$(rustup which --toolchain "${active_toolchain}" rustdoc)"
rust_bin_dir="$(dirname "${cargo_bin}")"

exec env \
  PATH="${rust_bin_dir}:${PATH}" \
  RUSTC="${rustc_bin}" \
  RUSTDOC="${rustdoc_bin}" \
  "${cargo_bin}" "$@"
