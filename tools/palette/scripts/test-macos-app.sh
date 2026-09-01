#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
palette_root=$(dirname "$script_dir")
build_app="$palette_root/build/Palette.app"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/palette-smoke.XXXXXX")
app="$test_dir/Palette Smoke.app"
cleanup() {
  smoke_pid=$(pgrep -f "^$app/Contents/MacOS/PaletteHost --smoke-test-log $log" || true)
  if [ -n "$smoke_pid" ]; then kill "$smoke_pid" 2>/dev/null || true; fi
  rm -rf "$test_dir"
}
trap cleanup EXIT HUP INT TERM
log="$test_dir/runtime.log"
data_dir="$test_dir/data"

"$script_dir/build-macos-app.sh" >/dev/null
ditto "$build_app" "$app"
plutil -replace CFBundleIdentifier -string "sh.palette.Desktop.Smoke" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
open -na "$app" --args --smoke-test-log "$log" --data-dir "$data_dir" --hotkey ctrl+shift+space

attempt=0
while [ "$attempt" -lt 80 ]; do
  if [ -f "$log" ] && grep -q '^SMOKE-COMPLETE$' "$log"; then break; fi
  sleep 0.25
  attempt=$((attempt + 1))
done

for event in delegate-launched status-item-ready global-shortcut-ready global-shortcut-toggle-ready ui-resource-ready webview-loaded webview-bridge-ready node-service-ready clipboard-capture-ready clipboard-retrieval-ready webview-reused panel-hidden-resident SMOKE-COMPLETE; do
  if ! grep -q "^${event}$" "$log" 2>/dev/null; then
    echo "macOS app smoke test missing event: $event" >&2
    [ -f "$log" ] && sed -n '1,120p' "$log" >&2
    exit 1
  fi
done

if grep -R -q 'palette-smoke-' "$data_dir"; then
  echo "Clipboard smoke-test plaintext leaked into persistent storage" >&2
  exit 1
fi

echo "macOS app bundle smoke test passed"
