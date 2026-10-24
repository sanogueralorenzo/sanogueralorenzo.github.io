#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]; then
    echo "Crest archive artifact guard skipped outside Xcode Cloud."
    exit 0
fi

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
    echo "Crest archive artifact guard skipped because xcodebuild already failed."
    exit 0
fi

fail() {
    echo "error: $1" >&2
    exit 64
}

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] \
    || fail "The Crest release workflow only permits archive actions."

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-}"
[ -n "$repository_path" ] \
    || fail "CI_PRIMARY_REPOSITORY_PATH is unavailable."

version_file="$repository_path/Config/Version.xcconfig"
[ -f "$version_file" ] \
    || fail "Config/Version.xcconfig is missing from the primary repository."

expected_version="$(
    sed -nE \
        's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' \
        "$version_file"
)"
[ -n "$expected_version" ] \
    || fail "Unable to resolve MARKETING_VERSION from Config/Version.xcconfig."

expected_build="${CI_BUILD_NUMBER:-}"
[ -n "$expected_build" ] \
    || fail "CI_BUILD_NUMBER is unavailable."

archive_path="${CI_ARCHIVE_PATH:-}"
[ -n "$archive_path" ] \
    || fail "CI_ARCHIVE_PATH is unavailable."
[ -d "$archive_path" ] \
    || fail "The Xcode Cloud archive does not exist at '$archive_path'."

archive_info="$archive_path/Info.plist"
[ -f "$archive_info" ] \
    || fail "The Xcode Cloud archive Info.plist is missing."

application_path="$(
    plutil -extract ApplicationProperties.ApplicationPath raw -o - "$archive_info" 2>/dev/null \
        || true
)"
case "$application_path" in
    Applications/*.app)
        ;;
    *)
        fail "The Xcode Cloud archive has an invalid application path '${application_path:-unset}'."
        ;;
esac

app_plist="$archive_path/Products/$application_path/Info.plist"
[ -f "$app_plist" ] \
    || fail "The archived app Info.plist is missing at '$app_plist'."

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_plist")"
actual_build="$(plutil -extract CFBundleVersion raw -o - "$app_plist")"
actual_bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$app_plist")"

[ "$actual_bundle_identifier" = "com.pauldavis.crest" ] \
    || fail "The archived app bundle identifier is '$actual_bundle_identifier', expected com.pauldavis.crest."
[ "$actual_version" = "$expected_version" ] \
    || fail "The archived app is version $actual_version, but Config/Version.xcconfig requires $expected_version."
[ "$actual_build" = "$expected_build" ] \
    || fail "The archived app build is $actual_build, but Xcode Cloud assigned $expected_build."

echo "Validated archived ${actual_bundle_identifier} version ${actual_version} (${actual_build}) before distribution."

# Xcode Cloud exports every iOS archive for ad hoc distribution too, and Apple
# grants Crest's Default Web Browser capability to development and App Store
# profiles only. That failed export fails the Archive action and skips the
# TestFlight post-action, so upload the App Store export here instead. Once the
# ad hoc export succeeds, Xcode Cloud uploads the build itself.
[ "${CI_PRODUCT_PLATFORM:-}" = "iOS" ] || exit 0

exported_package() {
    if [ -n "$1" ] && [ -d "$1" ]; then
        find "$1" -maxdepth 1 -type f -name '*.ipa' | head -n 1
    fi
}

if [ -n "$(exported_package "${CI_AD_HOC_SIGNED_APP_PATH:-}")" ]; then
    echo "Xcode Cloud exported ${actual_version} (${actual_build}) for every distribution; its TestFlight post-action uploads the build."
    exit 0
fi

app_store_package="$(exported_package "${CI_APP_STORE_SIGNED_APP_PATH:-}")"
[ -n "$app_store_package" ] \
    || fail "Xcode Cloud exported no App Store package to upload to TestFlight."

[ -n "${CREST_ASC_API_KEY_ID:-}" ] \
    || fail "Set the CREST_ASC_API_KEY_ID workflow secret to upload the App Store export to TestFlight."
[ -n "${CREST_ASC_API_ISSUER_ID:-}" ] \
    || fail "Set the CREST_ASC_API_ISSUER_ID workflow secret to upload the App Store export to TestFlight."
[ -n "${CREST_ASC_API_PRIVATE_KEY_BASE64:-}" ] \
    || fail "Set the CREST_ASC_API_PRIVATE_KEY_BASE64 workflow secret to upload the App Store export to TestFlight."

key_directory="$(mktemp -d)"
trap 'rm -rf "$key_directory"' EXIT
key_file="$key_directory/AuthKey_${CREST_ASC_API_KEY_ID}.p8"
(
    umask 077
    printf '%s' "$CREST_ASC_API_PRIVATE_KEY_BASE64" | base64 --decode > "$key_file"
) || fail "CREST_ASC_API_PRIVATE_KEY_BASE64 is not a base64-encoded App Store Connect key."

xcrun altool \
    --upload-package "$app_store_package" \
    --api-key "$CREST_ASC_API_KEY_ID" \
    --api-issuer "$CREST_ASC_API_ISSUER_ID" \
    --p8-file-path "$key_file" \
    || fail "altool could not upload ${actual_version} (${actual_build}) to TestFlight."

echo "Uploaded ${actual_bundle_identifier} version ${actual_version} (${actual_build}) to TestFlight from the App Store export."
