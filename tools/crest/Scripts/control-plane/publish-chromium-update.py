#!/usr/bin/env python3
"""Commit a built upstream update, publish its engine, and open its review."""
import argparse
import json
import os
from pathlib import Path
import re
import sys

from chromium_fork import ENGINE, REPO, read_json, run
import chromium_engine


def automatic_release_allowed(policy, *, enabled, default_branch, major_update):
    return (enabled == "true"
            and policy["automaticChannel"] == "development"
            and policy["integrationBranch"] == default_branch
            and (not major_update or policy["automaticMajorUpdates"]))


def append_release_note(catalog, identifier, note):
    """The release-note catalog text with `note` appended as its last entry.

    The catalog keeps literal characters beside older escapes, so its existing
    text is left exactly as it is instead of being serialized again.
    """
    entries = json.loads(catalog)["entries"]
    if identifier in entries:
        raise ValueError("This upstream update already has a release note")
    closing = "\n    }\n  }\n}\n"
    if not catalog.endswith(closing):
        raise ValueError("The release-note catalog no longer ends with its entries")
    fields = ",\n".join(f"      {json.dumps(name)}: {json.dumps(value, ensure_ascii=False)}"
                        for name, value in note.items())
    appended = f"{catalog[:-len(closing)]}\n    }},\n    {json.dumps(identifier)}: {{\n{fields}\n    }}\n  }}\n}}\n"
    if list(json.loads(appended)["entries"].items()) != list((entries | {identifier: note}).items()):
        raise ValueError("The release-note catalog did not take the update's entry last")
    return appended


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--ninja", type=Path, required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--major-update", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.base_sha):
        parser.error("Expected an immutable base commit")
    policy = read_json(REPO / ENGINE / "fork.json")
    base = policy["integrationBranch"]
    tag = read_json(REPO / ENGINE / "source.lock.json")["ungoogledMac"]["tag"]
    branch = f"codex/chromium-upstream-{tag}-{args.base_sha[:12]}"
    allowed_paths = {str(ENGINE / "source.lock.json"), str(ENGINE / "host-inputs.json")}
    changed = set(run("git", "diff", "--name-only", capture=True).splitlines())
    if not changed or not changed <= allowed_paths:
        parser.error("Upstream preparation changed unexpected files, or produced no update")
    if run("git", "ls-files", "--others", "--exclude-standard", capture=True).strip():
        parser.error("Unexpected untracked files in the update checkout")
    if run("git", "rev-parse", "HEAD", capture=True).strip() != args.base_sha:
        parser.error("The update checkout moved since preparation")
    run("git", "switch", "-c", branch)
    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run(REPO / "Scripts/set-version.sh", "--patch")
    notes_path = REPO / "Documentation/ReleaseNotes.json"
    entry = f"chromium-upstream-{tag.replace('.', '-')}-{args.base_sha[:12]}"
    note = {"category": "fixed", "message": f"Chromium is updated to {tag.split('-')[0]} with upstream security and compatibility fixes."}
    try:
        notes_path.write_text(append_release_note(notes_path.read_text(), entry, note))
    except ValueError as error:
        parser.error(str(error))
    run("git", "add", *sorted(allowed_paths), "Config/Version.xcconfig", "Documentation/ReleaseNotes.json")
    run(REPO / "Scripts/check-version.sh", "--fix-commit")
    run("git", "commit", "-m", f"Update Chromium to {tag}")
    head = run("git", "rev-parse", "HEAD", capture=True).strip()
    # A branch is never pushed until its engine is available by the exact input key.
    run(sys.executable, REPO / "Scripts/control-plane/publish-chromium-engine.py",
        "--source", args.source, "--ninja", args.ninja, "--repository", args.repository)
    run("git", "push", "origin", f"HEAD:refs/heads/{branch}")
    body = (f"Updates the maintained Chromium fork to upstream {tag}"
            f"{', a new Chromium milestone' if args.major_update else ''}.\n\n"
            "The unchanged Crest patch set applied without fuzz, and the performance engine built successfully. "
            f"Engine: `{chromium_engine.release_tag(chromium_engine.engine_key(REPO))}`.\n\n"
            "A compiled engine alone does not verify native browsing behavior. To try it, check out this branch "
            "and run `Scripts/install-local-macos-release.sh`, which installs Crest with this published engine. "
            "Merging publishes it to Development.")
    existing = json.loads(run("gh", "pr", "list", "--repo", args.repository, "--head", branch,
                              "--base", base, "--state", "open", "--json", "url", capture=True))
    url = existing[0]["url"] if existing else run("gh", "pr", "create", "--repo", args.repository,
        "--base", base, "--head", branch, "--title", f"Update Chromium to {tag}", "--body", body, capture=True).strip()
    default_branch = json.loads(run("gh", "api", f"repos/{args.repository}", capture=True))["default_branch"]
    promote = automatic_release_allowed(policy, enabled=os.environ.get("CHROMIUM_AUTO_RELEASE"),
        default_branch=default_branch, major_update=args.major_update)
    print(url)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"pull_request={url}\nhead={head}\nautomatic_release={str(promote).lower()}\n")


if __name__ == "__main__":
    main()
