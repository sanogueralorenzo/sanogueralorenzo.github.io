#!/bin/bash
set -euo pipefail

configuration=Debug
build_only=false
for option in "$@"; do
    case "$option" in
        --release) configuration=Release ;;
        --build-only) build_only=true ;;
        *) echo "Usage: $0 [--release] [--build-only]" >&2; exit 2 ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    selected_developer="$(xcode-select -p)"
    if [[ "$selected_developer" == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app ]]; then
        selected_developer=/Applications/Xcode.app/Contents/Developer
    fi
    export DEVELOPER_DIR="$selected_developer"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Install XcodeGen with brew install xcodegen, then rerun this command." >&2
    exit 1
fi

xcodegen generate
derived_data="${LEAN_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/LeanNextLocal}"
compilation_conditions='$(inherited) CREST_REVIEW_BUILD'
if [[ "$configuration" == Debug ]]; then
    compilation_conditions="$compilation_conditions DEBUG"
fi

# Local builds use an ad-hoc signature and their own identity. Apple's managed
# entitlements require the upstream team's provisioning profiles.
xcodebuild -quiet -project Crest.xcodeproj -scheme Crest -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= \
    ENABLE_HARDENED_RUNTIME=NO \
    CREST_MAC_BUNDLE_IDENTIFIER=dev.leanbrowser.LeanNext.review \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="$compilation_conditions" build

app="$derived_data/Build/Products/$configuration/LeanNext.app"
codesign --verify --deep --strict "$app"
echo "Built $app"

if [[ "$build_only" == false ]]; then
    open --env CREST_ISOLATED_SESSION=1 --env CREST_ISOLATED_PERSISTENCE_ID=lean-next-local "$app"
fi
