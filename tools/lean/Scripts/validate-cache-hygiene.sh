#!/bin/zsh
set -euo pipefail

repository_root="${1:-${0:A:h:h}}"

if [[ ! -d "$repository_root" ]]; then
  print -u2 "Cache-hygiene root does not exist: $repository_root"
  exit 1
fi

generated_paths=()
generated_directories=(
  DerivedData
  build
  .build
  .swiftpm
)

for generated_directory in "${generated_directories[@]}"; do
  candidate="$repository_root/$generated_directory"
  if [[ -e "$candidate" ]]; then
    generated_paths+=("$candidate")
  fi
done

while IFS= read -r generated_file; do
  generated_paths+=("$generated_file")
done < <(
  find "$repository_root" \
    -path "$repository_root/.git" -prune -o \
    \( \
      -name '*.xcresult' -o \
      -name '*.xctestproducts' -o \
      -name '*.xcarchive' -o \
      -name '*.ipa' -o \
      -name '*.dSYM' -o \
      -name '*.dSYM.zip' \
    \) -print
)

if (( ${#generated_paths[@]} > 0 )); then
  print -u2 "Repository-owned Xcode/Swift build artifacts must be removed before handoff:"
  printf '  %s\n' "${generated_paths[@]}" >&2
  exit 1
fi

print "Build-cache hygiene validation passed."
