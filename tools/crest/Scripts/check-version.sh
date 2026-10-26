#!/bin/zsh
set -euo pipefail

script_root="${0:A:h:h}"
repository_root="${CREST_VERSION_REPOSITORY_ROOT:-$script_root}"
mode="${1:-}"

if [[ -n "$mode" && "$mode" != "--static" && "$mode" != "--fix-commit" ]]; then
  print -u2 "Usage: Scripts/check-version.sh [--static|--fix-commit]"
  exit 64
fi

fail() {
  print -u2 "error: $1"
  exit 1
}

is_strict_semver() {
  print -r -- "$1" | grep -Eq \
    '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

version_file="$repository_root/Config/Version.xcconfig"
project_file="$repository_root/project.yml"
project_bundle="$repository_root/Crest.xcodeproj"
mac_plist="$repository_root/CrestMac/Configuration/Crest-Info.plist"
mobile_plist="$repository_root/CrestMobile/Configuration/CrestMobile-Info.plist"
release_note_catalog_check="$script_root/Scripts/release_note_catalog.py"

[[ -f "$version_file" ]] || fail "Config/Version.xcconfig is missing."
[[ -f "$project_file" ]] || fail "project.yml is missing."
[[ -f "$release_note_catalog_check" ]] \
  || fail "Scripts/release_note_catalog.py is missing."

setting_count="$({ grep -Evc '^[[:space:]]*(//.*|#.*)?$' "$version_file" || true; } | tr -d '[:space:]')"
[[ "$setting_count" == "1" ]] \
  || fail "Config/Version.xcconfig must contain only MARKETING_VERSION."

marketing_setting_count="$({ grep -Ec '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' "$version_file" || true; } | tr -d '[:space:]')"
[[ "$marketing_setting_count" == "1" ]] \
  || fail "Config/Version.xcconfig must define MARKETING_VERSION exactly once."

if grep -Eq '^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=' "$version_file"; then
  fail "Xcode Cloud owns distributed build numbers; keep CURRENT_PROJECT_VERSION out of Config/Version.xcconfig."
fi

marketing_version="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' "$version_file")"
is_strict_semver "$marketing_version" \
  || fail "MARKETING_VERSION must use strict X.Y.Z SemVer without leading zeroes or suffixes."

if [[ "$mode" == "--fix-commit" ]]; then
  if git -C "$repository_root" diff --cached --quiet -- Config/Version.xcconfig; then
    fail "Fix commits must stage Config/Version.xcconfig with their patch version increase."
  fi

  head_version="$({
    git -C "$repository_root" show HEAD:Config/Version.xcconfig 2>/dev/null \
      | sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p'
  } || true)"
  staged_version="$({
    git -C "$repository_root" show :Config/Version.xcconfig 2>/dev/null \
      | sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p'
  } || true)"

  is_strict_semver "$head_version" || fail "HEAD does not contain a valid Crest marketing version."
  is_strict_semver "$staged_version" || fail "The staged Crest marketing version is invalid."
  [[ "$marketing_version" == "$staged_version" ]] \
    || fail "The working and staged Crest marketing versions differ; stage Config/Version.xcconfig again."

  head_parts=("${(@s:.:)head_version}")
  staged_parts=("${(@s:.:)staged_version}")
  [[ "${staged_parts[1]}.${staged_parts[2]}" == "${head_parts[1]}.${head_parts[2]}" ]] \
    || fail "A fix commit must increment the patch version without changing the release line."
  (( staged_parts[3] > head_parts[3] )) \
    || fail "A fix commit must increment the patch version."

  python3 "$release_note_catalog_check" \
    --repository-root "$repository_root" \
    --require-staged-entry
else
  python3 "$release_note_catalog_check" --repository-root "$repository_root"
fi

for plist in "$mac_plist" "$mobile_plist"; do
  [[ -f "$plist" ]] || fail "${plist#$repository_root/} is missing."

  short_version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist")"
  build_version="$(plutil -extract CFBundleVersion raw -o - "$plist")"
  [[ "$short_version" == '$(MARKETING_VERSION)' ]] \
    || fail "${plist#$repository_root/} must substitute \$(MARKETING_VERSION)."
  [[ "$build_version" == '$(CURRENT_PROJECT_VERSION)' ]] \
    || fail "${plist#$repository_root/} must substitute \$(CURRENT_PROJECT_VERSION)."
done

for configuration in Debug Release; do
  configured_path="$(awk -v configuration="$configuration" '
    $0 == "configFiles:" { in_config_files = 1; next }
    in_config_files && $0 !~ /^  / { in_config_files = 0 }
    in_config_files {
      key = $1
      sub(/:$/, "", key)
      if (key == configuration) {
        print $2
        exit
      }
    }
  ' "$project_file")"

  [[ "$configured_path" == "Config/Version.xcconfig" ]] \
    || fail "$configuration must inherit Config/Version.xcconfig in project.yml."
done

grep -Eq '^[[:space:]]+CURRENT_PROJECT_VERSION:[[:space:]]+"1"[[:space:]]*$' "$project_file" \
  || fail "project.yml must keep CURRENT_PROJECT_VERSION at the local fallback value 1."

if [[ -z "$mode" ]]; then
  [[ -d "$project_bundle" ]] || fail "Crest.xcodeproj is missing; run XcodeGen first."

  for target in Crest CrestMobile; do
    for configuration in Debug Release; do
      if ! build_settings="$(
        xcodebuild \
          -project "$project_bundle" \
          -target "$target" \
          -configuration "$configuration" \
          -showBuildSettings \
          2>&1
      )"; then
        print -u2 -- "$build_settings"
        fail "Unable to resolve $target $configuration build settings."
      fi

      resolved_marketing_version="$(
        print -r -- "$build_settings" \
          | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }'
      )"
      resolved_build_version="$(
        print -r -- "$build_settings" \
          | awk -F ' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }'
      )"

      [[ "$resolved_marketing_version" == "$marketing_version" ]] \
        || fail "$target $configuration resolves MARKETING_VERSION as '${resolved_marketing_version:-unset}', expected $marketing_version."
      [[ "$resolved_build_version" == "1" ]] \
        || fail "$target $configuration resolves CURRENT_PROJECT_VERSION as '${resolved_build_version:-unset}', expected local fallback 1."
    done
  done
fi

if [[ "$mode" == "--fix-commit" ]]; then
  print "Validated fix commit patch version from $head_version to $staged_version."
elif [[ "$mode" == "--static" ]]; then
  print "Validated Crest $marketing_version version metadata (static)."
else
  print "Validated Crest $marketing_version version metadata."
fi
