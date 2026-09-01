#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
palette_root=$(dirname "$script_dir")
output="$palette_root/build/Palette.app"
node_version=${PALETTE_NODE_VERSION:-22.18.0}

case "$output" in
  "$palette_root"/build/*.app) ;;
  *) echo "Refusing to replace an app outside Palette's build directory" >&2; exit 1 ;;
esac

architecture=$(uname -m)
case "$architecture" in
  arm64) node_arch=arm64 ;;
  x86_64) node_arch=x64 ;;
  *) echo "Unsupported macOS architecture: $architecture" >&2; exit 1 ;;
esac

runtime_name="node-v${node_version}-darwin-${node_arch}"
runtime_cache="$palette_root/.cache/$runtime_name"
node_runtime="$runtime_cache/bin/node"
if [ ! -x "$node_runtime" ]; then
  mkdir -p "$palette_root/.cache"
  download_dir=$(mktemp -d "${TMPDIR:-/tmp}/palette-node.XXXXXX")
  trap 'rm -rf "$download_dir"' EXIT HUP INT TERM
  archive="$runtime_name.tar.gz"
  base_url="https://nodejs.org/dist/v${node_version}"
  curl -fsSL "$base_url/$archive" -o "$download_dir/$archive"
  curl -fsSL "$base_url/SHASUMS256.txt" -o "$download_dir/SHASUMS256.txt"
  expected=$(awk -v file="$archive" '$2 == file { print $1 }' "$download_dir/SHASUMS256.txt")
  actual=$(shasum -a 256 "$download_dir/$archive" | awk '{ print $1 }')
  if [ -z "$expected" ] || [ "$actual" != "$expected" ]; then
    echo "Node runtime checksum verification failed" >&2
    exit 1
  fi
  tar -xzf "$download_dir/$archive" -C "$download_dir"
  rm -rf "$runtime_cache"
  mv "$download_dir/$runtime_name" "$runtime_cache"
  rm -rf "$download_dir"
  trap - EXIT HUP INT TERM
fi

cd "$palette_root"
npm run build
npm run build:daemon
cargo build --release --manifest-path native/rust-indexer/Cargo.toml

bundle_dir=$(mktemp -d "${TMPDIR:-/tmp}/palette-app.XXXXXX")
trap 'rm -rf "$bundle_dir"' EXIT HUP INT TERM
app="$bundle_dir/Palette.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources/ui" "$app/Contents/Resources/node"
swiftc -parse-as-library native/macos/PaletteHost.swift \
  -o "$app/Contents/MacOS/PaletteHost" \
  -framework AppKit -framework Carbon -framework Security -framework UserNotifications -framework WebKit
cp native/macos/Info.plist "$app/Contents/Info.plist"
cp -R dist/ui/. "$app/Contents/Resources/ui/"
cp dist/node/node-daemon.mjs "$app/Contents/Resources/node/node-daemon.mjs"
cp native/rust-indexer/target/release/palette-indexer "$app/Contents/Helpers/palette-indexer"
cp "$node_runtime" "$app/Contents/Helpers/node"
chmod +x "$app/Contents/MacOS/PaletteHost" "$app/Contents/Helpers/node" "$app/Contents/Helpers/palette-indexer"
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"

mkdir -p "$palette_root/build"
rm -rf "$output"
mv "$app" "$output"
echo "$output"
