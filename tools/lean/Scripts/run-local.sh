#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--build-only" ) ]]; then
    echo "Usage: $0 [--build-only]" >&2
    exit 2
fi

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
derived_data="$HOME/Library/Developer/Xcode/DerivedData/LeanNextLocal"

# Local builds use an ad-hoc signature and their own identity. Apple's managed
# entitlements require the upstream team's provisioning profiles.
xcodebuild -quiet -project Crest.xcodeproj -scheme Crest -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= \
    CREST_MAC_BUNDLE_IDENTIFIER=dev.leanbrowser.LeanNext.review \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG CREST_REVIEW_BUILD' build

app="$derived_data/Build/Products/Debug/LeanNext.app"
codesign --verify --deep --strict "$app"
echo "Built $app"

if [[ "${1:-}" != "--build-only" ]]; then
    open --env CREST_ISOLATED_SESSION=1 --env CREST_ISOLATED_PERSISTENCE_ID=lean-next-local "$app"
fi
