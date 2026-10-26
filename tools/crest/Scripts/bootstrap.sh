#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  print -u2 "XcodeGen is required. Install it, then rerun Scripts/bootstrap.sh."
  exit 1
fi

xcodegen generate

skill_link=".claude/skills/crest-contribution"
if [[ -e "$skill_link" && ! -L "$skill_link" ]]; then
  print -u2 "$skill_link exists but is not a symlink to ../../.agents/skills/crest-contribution. Move it aside, then rerun Scripts/bootstrap.sh."
  exit 1
fi
if [[ ! -f "$skill_link/SKILL.md" ]]; then
  mkdir -p "${skill_link:h}"
  ln -sfn ../../.agents/skills/crest-contribution "$skill_link"
  print "Linked $skill_link for Claude Code"
fi

Scripts/check-version.sh
Scripts/validate-identity.sh
Scripts/validate-cache-hygiene.sh

print "Generated $repository_root/Crest.xcodeproj"
