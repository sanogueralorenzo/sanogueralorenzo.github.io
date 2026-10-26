#!/bin/zsh
set -euo pipefail

script_repository_root="${0:A:h:h}"
repository_root="${CREST_FORMAT_REPOSITORY_ROOT:-$script_repository_root}"
base_ref=""
typeset -a explicit_paths

usage() {
  print -u2 "Usage: Scripts/check-swift-format.sh [--base GIT_REF] [-- PATH ...]"
}

while (( $# > 0 )); do
  case "$1" in
    --base)
      (( $# >= 2 )) || { usage; exit 64; }
      base_ref="$2"
      shift 2
      ;;
    --)
      shift
      explicit_paths+=("$@")
      break
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

cd "$repository_root"
[[ -d .git || -f .git ]] || { print -u2 "error: $repository_root is not a Git worktree."; exit 2; }
[[ -f .swift-format ]] || { print -u2 "error: .swift-format is missing."; exit 2; }

typeset -a candidate_paths
if (( ${#explicit_paths[@]} > 0 )); then
  candidate_paths+=("${explicit_paths[@]}")
else
  if [[ -n "$base_ref" ]]; then
    git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null \
      || { print -u2 "error: unknown base ref '$base_ref'."; exit 2; }
    while IFS= read -r -d '' changed_file; do
      candidate_paths+=("$changed_file")
    done < <(git diff --name-only -z --diff-filter=ACMR "${base_ref}...HEAD" -- '*.swift')
  fi

  while IFS= read -r -d '' changed_file; do
    candidate_paths+=("$changed_file")
  done < <(git diff --name-only -z --diff-filter=ACMR -- '*.swift')
  while IFS= read -r -d '' changed_file; do
    candidate_paths+=("$changed_file")
  done < <(git diff --cached --name-only -z --diff-filter=ACMR -- '*.swift')
  while IFS= read -r -d '' changed_file; do
    candidate_paths+=("$changed_file")
  done < <(git ls-files --others --exclude-standard -z -- '*.swift')
fi

typeset -A seen_paths
typeset -a swift_paths
for changed_file in "${candidate_paths[@]}"; do
  [[ "$changed_file" == *.swift && -f "$changed_file" ]] || continue
  # Generated sources follow their generator, not the formatter.
  [[ "$changed_file" != */Generated/* ]] || continue
  [[ -z "${seen_paths[$changed_file]-}" ]] || continue
  seen_paths[$changed_file]=1
  swift_paths+=("$changed_file")
done

if (( ${#swift_paths[@]} == 0 )); then
  print "No changed Swift files to lint."
  exit 0
fi

formatter="${CREST_SWIFT_FORMAT:-}"
if [[ -z "$formatter" ]]; then
  formatter="$(xcrun --find swift-format 2>/dev/null || true)"
fi
[[ -n "$formatter" && -x "$formatter" ]] \
  || { print -u2 "error: swift-format is unavailable in the active Xcode toolchain."; exit 69; }

"$formatter" lint --strict --configuration "$repository_root/.swift-format" "${swift_paths[@]}"
print "Validated swift-format for ${#swift_paths[@]} changed Swift file(s)."
