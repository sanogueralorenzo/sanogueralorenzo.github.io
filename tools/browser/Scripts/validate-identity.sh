#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

required_paths=(
  CrestShared
  CrestMac
  CrestMobile
  CrestTests
  CrestMobileTests
  CrestTestFixtures
  Documentation/ARCHITECTURE.md
  CrestShared/Resources/CrestIcon/Crest.icon
  project.yml
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "$required_path" ]]; then
    print -u2 "Missing required Crest path: $required_path"
    exit 1
  fi
done

prototype_root="Bro""wser"
prototype_tests="${prototype_root}Tests"
prototype_ui_tests="${prototype_root}UITests"
prototype_project="${prototype_root}.xcodeproj"

if [[ -e "$prototype_root" || -e "$prototype_tests" || -e "$prototype_ui_tests" || -e "$prototype_project" ]]; then
  print -u2 "A prototype-named top-level project path still exists."
  exit 1
fi

prototype_product="cae""lura"
prototype_bundle="com.pauldavis.${prototype_root:l}"
prototype_environment="${prototype_root:u}_"
prototype_import="@testable import ${prototype_root}"

if rg -n -i \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "${prototype_product}|${prototype_bundle}|${prototype_project}|${prototype_import}" \
  .; then
  print -u2 "Prototype product identity remains in the repository."
  exit 1
fi

if rg -n \
  --glob '!Scripts/validate-identity.sh' \
  --glob '!*.xcuserstate' \
  --glob '!DerivedData/**' \
  "(^|[^[:alnum:]_])${prototype_environment}" \
  .; then
  print -u2 "Prototype launch environment remains in the repository."
  exit 1
fi

rg -q '^name: Crest$' project.yml
rg -q '^  Crest:$' project.yml
rg -q '^  CrestMobile:$' project.yml
rg -q 'CREST_MAC_BUNDLE_IDENTIFIER: com\.pauldavis\.crest$' project.yml
rg -q 'CREST_MOBILE_BUNDLE_IDENTIFIER: com\.pauldavis\.crest$' project.yml
rg -q 'PRODUCT_MODULE_NAME: Crest$' project.yml
rg -q 'PRODUCT_MODULE_NAME: CrestMobile$' project.yml

print "Crest identity validation passed."
