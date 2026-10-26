#!/bin/zsh
set -euo pipefail

# Builds Crest's dual-engine Mac app the way the release workflow does, signs
# it with this Mac's Developer ID identity, and installs it in /Applications.
# The Chromium engine is the published one matching this checkout's engine
# inputs; set CREST_CHROMIUM_APP to a locally built Chromium.app to use that
# instead.

repository_root="${0:A:h:h}"
application_path="/Applications/Crest.app"
repository="pauljoda/Crest"
team_id="3U2R97HLXF"
signing_identity="Developer ID Application"
provisioning_profile="Crest Developer ID"
development_appcast_url="https://raw.githubusercontent.com/pauljoda/Crest/updates/appcast-development.xml"
derived_data_path="${CREST_LOCAL_RELEASE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Crest-LocalRelease}"
engine_cache_root="${CREST_ENGINE_CACHE:-$HOME/Library/Caches/Crest-local-release}"
lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

cd "$repository_root"

signing_identity_hash="$(
  security find-identity -v -p codesigning \
    | awk "/${signing_identity}: .*\\(${team_id}\\)/ { print \$2; exit }"
)"
if [[ -z "$signing_identity_hash" ]]; then
  print -u2 "Crest's Developer ID Application identity is not installed."
  exit 1
fi

profile_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
profile_found=false
if [[ -d "$profile_directory" ]]; then
  for profile_path in "$profile_directory"/*; do
    [[ -f "$profile_path" ]] || continue
    profile_name="$({
      security cms -D -i "$profile_path" 2>/dev/null \
        | plutil -extract Name raw - 2>/dev/null
    } || true)"
    if [[ "$profile_name" == "$provisioning_profile" ]]; then
      profile_found=true
    fi
    [[ "$profile_found" == true ]] && break
  done
fi
if [[ "$profile_found" != true ]]; then
  print -u2 "The $provisioning_profile provisioning profile is not installed."
  exit 1
fi

# The same lookup as the Xcode build's core phase (build-apple-core.py).
dotnet=""
for candidate in "${CREST_DOTNET:-}" "$(command -v dotnet || true)" \
  "$HOME/.dotnet/dotnet" /usr/local/share/dotnet/dotnet; do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    dotnet="$candidate"
    break
  fi
done
if [[ -z "$dotnet" ]]; then
  print -u2 "Install the SDK in CrestCore/global.json, or run Scripts/control-plane/install-dotnet.sh."
  exit 1
fi

build_number="${CREST_LOCAL_BUILD_NUMBER:-}"
if [[ -z "$build_number" && -d "$application_path" ]]; then
  build_number="$({
    defaults read "$application_path/Contents/Info" CFBundleVersion
  } 2>/dev/null || true)"
fi
build_number="${build_number:-1}"
if [[ -z "${CREST_LOCAL_BUILD_NUMBER:-}" && "$build_number" =~ '^[0-9]+$' ]]; then
  published_build_number="$({
    curl --fail --silent --show-error --location \
      --connect-timeout 3 \
      --max-time 5 \
      "$development_appcast_url" \
      | sed -n \
        's|.*<sparkle:version>\([0-9][0-9]*\)</sparkle:version>.*|\1|p' \
      | sed -n '1p'
  } || true)"
  if [[ "$published_build_number" =~ '^[0-9]+$' ]] \
    && (( published_build_number > build_number )); then
    build_number="$published_build_number"
  fi
fi
if [[ ! "$build_number" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
  print -u2 "Invalid local build number: $build_number"
  exit 1
fi

release_root="$(mktemp -d "${TMPDIR%/}/crest-local-release.XXXXXX")"
archive_path="$release_root/Crest.xcarchive"
export_path="$release_root/export"
built_application_path="$release_root/product/Crest.app"
previous_application_path="$release_root/Crest.previous.app"
installation_staging_path="/Applications/.Crest-local-install-${$}.app"
installation_complete=false

cleanup() {
  if [[ -e "$installation_staging_path" ]]; then
    find "$installation_staging_path" -depth -delete 2>/dev/null || true
  fi
  if [[ "$installation_complete" != true \
    && ! -e "$application_path" \
    && -e "$previous_application_path" ]]; then
    mv "$previous_application_path" "$application_path" 2>/dev/null || true
  fi
  # Unregister the intermediate apps, including the WebKit copy the archive
  # leaves in Derived Data, so LaunchServices only resolves Crest to the
  # installed app.
  for intermediate in "$export_path/Crest.app" "$built_application_path" "$previous_application_path" \
    "$archive_path/Products/Applications/Crest.app" \
    "$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates/Crest/InstallationBuildProductsLocation/Applications/Crest.app"; do
    [[ -e "$intermediate" ]] && "$lsregister" -u "$intermediate" >/dev/null 2>&1 || true
  done
  find "$release_root" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# --- Chromium engine: resolved first, so a missing engine stops the install
# before the builds. The published engine is cached by its tag. ---
if [[ -n "${CREST_CHROMIUM_APP:-}" ]]; then
  engine_path="${CREST_CHROMIUM_APP:A}"
  engine_label="local engine at $engine_path"
else
  engine_tag="$(python3 Scripts/control-plane/chromium_engine.py tag)"
  engine_asset="$(python3 Scripts/control-plane/chromium_engine.py asset)"
  engine_path="$engine_cache_root/$engine_tag/Chromium.app"
  engine_label="$engine_tag"
  if [[ ! -d "$engine_path" ]]; then
    if ! command -v gh >/dev/null; then
      print -u2 "Install the GitHub CLI to download $engine_tag, or set CREST_CHROMIUM_APP."
      exit 1
    fi
    print "Downloading Chromium engine $engine_tag..."
    download_path="$release_root/engine-download"
    mkdir -p "$download_path"
    if ! gh release download "$engine_tag" \
      --repo "$repository" \
      --pattern "$engine_asset" \
      --pattern "${engine_asset}.sha256" \
      --dir "$download_path"; then
      print -u2 "No Chromium engine is published for this checkout's engine inputs ($engine_tag)."
      print -u2 "Build and publish it as described in CrestEngines/Chromium/README.md, or set CREST_CHROMIUM_APP."
      exit 1
    fi
    (cd "$download_path" && shasum -a 256 -c "${engine_asset}.sha256")
    ditto -x -k "$download_path/$engine_asset" "$download_path/extracted"
    [[ -d "$download_path/extracted/Chromium.app" ]]
    # Keep only the engine this checkout needs.
    mkdir -p "$engine_cache_root"
    find "$engine_cache_root" -mindepth 1 -maxdepth 1 -name 'chromium-engine-*' \
      -exec rm -rf {} + 2>/dev/null || true
    mv "$download_path/extracted" "$engine_cache_root/$engine_tag"
  fi
fi
if [[ ! -f "$engine_path/Contents/Info.plist" ]]; then
  print -u2 "No Chromium.app at $engine_path."
  exit 1
fi

print "Building Crest Release ($build_number) with production services and $engine_label..."

# --- Entitlements: Xcode's Developer ID export of the WebKit composition
# resolves the entitlements Crest is signed with, as in the release. ---
xcodebuild archive \
  -quiet \
  -project Crest.xcodeproj \
  -scheme Crest \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data_path" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CREST_DEFAULT_UPDATE_CHANNEL=development \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" \
  CREST_PROVISIONING_PROFILE_SPECIFIER="$provisioning_profile"

xcodebuild -exportArchive \
  -quiet \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist Config/DeveloperIDExportOptions.plist

[[ -d "$export_path/Crest.app" ]]
exported_entitlements="$release_root/exported-entitlements.plist"
codesign -d --entitlements :- "$export_path/Crest.app" \
  > "$exported_entitlements" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.developer.icloud-container-environment' \
  "$exported_entitlements")" == "Production" ]]
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$exported_entitlements" >/dev/null 2>&1; then
  print -u2 "The product entitlements must not enable the app sandbox; it would strand installed data."
  exit 1
fi

# --- Crest: the native core and interface framework, packaged with the
# engine. ---
(cd CrestCore && "$dotnet" publish src/CrestCore.Native -c Release -r osx-arm64 --nologo -v quiet)
core_library="$PWD/CrestCore/src/CrestCore.Native/bin/Release/net10.0/osx-arm64/publish/CrestCore.Native.dylib"
[[ -f "$core_library" ]]

xcodebuild build \
  -quiet \
  -project Crest.xcodeproj \
  -scheme CrestChromiumUIProduct \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO
ui_framework="$derived_data_path/Build/Products/Release/CrestChromiumUIProduct.framework"
[[ -d "$ui_framework" ]]
# The engine and launcher resolve these by name; a Release build that drops
# them from the export table builds cleanly and then cannot start.
for entry in crest_chromium_ui_start crest_native_host_run; do
  if ! nm -gU "$ui_framework/CrestChromiumUIProduct" | grep -q "_${entry}\$"; then
    print -u2 "CrestChromiumUIProduct does not export $entry."
    exit 1
  fi
done

mkdir -p "${built_application_path:h}"
CREST_DEFAULT_UPDATE_CHANNEL=development python3 Scripts/control-plane/package-chromium-host.py \
  --browser "$engine_path" \
  --product \
  --distribution \
  --ui "$ui_framework" \
  --core "$core_library" \
  --entitlements "$exported_entitlements" \
  --provisioning-profile "$profile_path" \
  --signing-identity "$signing_identity_hash" \
  --output "$built_application_path"

codesign --verify --deep --strict --verbose=2 "$built_application_path"
[[ "$(defaults read "$built_application_path/Contents/Info" CFBundleIdentifier)" \
  == "com.pauldavis.crest" ]]
[[ "$(defaults read "$built_application_path/Contents/Info" CFBundleVersion)" == "$build_number" ]]

# Match only the installed app's own main executable, whatever it is named:
# simulators host processes that are also named Crest, and engine helpers run
# from Contents/Frameworks; neither must block a desktop install.
installed_crest_pattern="^${application_path}/Contents/MacOS/"
if pgrep -f "$installed_crest_pattern" >/dev/null 2>&1; then
  osascript -e 'tell application "Crest" to quit'
  for _ in {1..100}; do
    pgrep -f "$installed_crest_pattern" >/dev/null 2>&1 || break
    sleep 0.1
  done
fi
if pgrep -f "$installed_crest_pattern" >/dev/null 2>&1; then
  print -u2 "Crest did not quit; the existing application was not replaced."
  exit 1
fi

ditto "$built_application_path" "$installation_staging_path"
codesign --verify --deep --strict --verbose=2 "$installation_staging_path"
if [[ -e "$application_path" ]]; then
  mv "$application_path" "$previous_application_path"
fi
mv "$installation_staging_path" "$application_path"
installation_complete=true

codesign --verify --deep --strict --verbose=2 "$application_path"
"$lsregister" -f "$application_path" >/dev/null 2>&1 || true
open "$application_path"
print "Installed and launched local Crest Release ($build_number) with $engine_label."
