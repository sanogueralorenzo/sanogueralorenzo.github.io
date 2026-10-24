#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]; then
    echo "Crest pre-archive version guard skipped outside Xcode Cloud."
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

case "${CI_PRODUCT_PLATFORM:-}" in
    iOS)
        expected_scheme="CrestMobile"
        destination="generic/platform=iOS"
        ;;
    macOS)
        expected_scheme="Crest"
        destination="generic/platform=macOS"
        ;;
    *)
        fail "Unsupported Xcode Cloud platform '${CI_PRODUCT_PLATFORM:-unset}'."
        ;;
esac

[ "${CI_XCODE_SCHEME:-}" = "$expected_scheme" ] \
    || fail "${CI_PRODUCT_PLATFORM} archives must use the ${expected_scheme} scheme."

version_file="$repository_path/Config/Version.xcconfig"
[ -f "$version_file" ] \
    || fail "Config/Version.xcconfig is missing from the primary repository."

project_file="$repository_path/Crest.xcodeproj/project.pbxproj"
[ -f "$project_file" ] \
    || fail "Crest.xcodeproj/project.pbxproj is missing from the primary repository."

expected_build="${CI_BUILD_NUMBER:-}"
case "$expected_build" in
    ''|*[!0-9]*)
        fail "CI_BUILD_NUMBER must be a positive integer; received '${expected_build:-unset}'."
        ;;
    0)
        fail "CI_BUILD_NUMBER must be a positive integer; received '0'."
        ;;
esac

# Xcode Cloud exposes its monotonically increasing build number through
# CI_BUILD_NUMBER, but it does not override CURRENT_PROJECT_VERSION for the
# archive. Stamp the generated project in this ephemeral checkout so the
# distributed artifact uses the number Xcode Cloud assigned.
sed -i '' -E \
    "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $expected_build;/g" \
    "$project_file"

expected_version="$(
    sed -nE \
        's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' \
        "$version_file"
)"
[ -n "$expected_version" ] \
    || fail "Unable to resolve MARKETING_VERSION from Config/Version.xcconfig."

if ! build_settings="$(
    xcodebuild \
        -project "$repository_path/Crest.xcodeproj" \
        -scheme "$expected_scheme" \
        -configuration Release \
        -destination "$destination" \
        -showBuildSettings \
        2>&1
)"; then
    echo "$build_settings" >&2
    fail "Unable to resolve ${expected_scheme} Release build settings."
fi

resolved_version="$(
    echo "$build_settings" \
        | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }'
)"
[ "$resolved_version" = "$expected_version" ] \
    || fail "${expected_scheme} Release resolves MARKETING_VERSION as '${resolved_version:-unset}', expected $expected_version."

resolved_build="$(
    echo "$build_settings" \
        | awk -F ' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }'
)"
[ "$resolved_build" = "$expected_build" ] \
    || fail "${expected_scheme} Release resolves CURRENT_PROJECT_VERSION as '${resolved_build:-unset}', expected Xcode Cloud build $expected_build."

echo "Validated ${expected_scheme} Release version $resolved_version ($resolved_build) before the Xcode Cloud archive."
