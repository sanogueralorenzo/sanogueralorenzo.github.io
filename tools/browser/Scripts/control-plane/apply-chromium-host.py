#!/usr/bin/env python3
"""Validate or install Crest's native host overlay into its pinned external Chromium tree."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

# The engine contract's headers in CrestContracts/include that the binding
# compiles against. chromium_engine.py keys the published engine on them.
ENGINE_CONTRACT = ("crest_core.h", "crest_app.h", "crest_engine.h", "crest_engine_contract.h")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--apply", action="store_true", help="Install after validation; default is read-only")
    args = parser.parse_args()
    source = args.source.resolve()
    repo = Path(__file__).resolve().parents[2]
    host = repo / "CrestEngines/Chromium"
    if source == repo or repo in source.parents:
        parser.error("Use the external, pinned Chromium checkout")
    inputs = json.loads((host / "host-inputs.json").read_text())
    states = {}
    for name, hashes in inputs.items():
        path = source / name
        if not path.is_file():
            parser.error(f"Missing pinned Chromium input: {name}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        state = next((key for key, value in hashes.items() if value == digest), None)
        if state is None:
            parser.error(f"Changed Chromium input; review against the pinned host patch: {name}")
        states[name] = state
    # Each input was matched against its reviewed before/after hash. New host
    # revisions may introduce another input after earlier files were installed.
    chunks = (host / "Patches/native-host.patch").read_text().split("--- a/")[1:]
    pending = "".join("--- a/" + chunk for chunk in chunks
                      if states[chunk.splitlines()[0]] == "before")
    if pending:
        subprocess.run(["patch", "--dry-run", "-p1"], input=pending,
                       text=True, cwd=source, check=True)
    state = "after" if not pending else "pending"
    if not args.apply:
        print(f"Host inputs validated ({state}); no source was changed.")
        return
    # Never alter inputs under an active compiler. The build wrapper uses a
    # dedicated process group, but other Ninja invocations must also be quiet.
    processes = subprocess.check_output(["ps", "-axo", "comm=,args="], text=True)
    if any("ninja" in line.split()[0] and "CrestBaseline" in line for line in processes.splitlines() if line.split()):
        parser.error("Stop the task's Chromium Ninja build before installing the overlay")
    if pending:
        subprocess.run(["patch", "-p1"], input=pending, text=True, cwd=source, check=True)
    for name, hashes in inputs.items():
        if hashlib.sha256((source / name).read_bytes()).hexdigest() != hashes["after"]:
            parser.error(f"Host patch did not produce its reviewed output: {name}")
    # An installed file takes the time it was installed, never its source's:
    # an object built after the source was edited, from the previous install,
    # must still be older than the file that replaces its input, or Ninja
    # links it again.
    for path in (host / "Overlay").rglob("*"):
        if path.is_file():
            destination = source / path.relative_to(host / "Overlay")
            destination.parent.mkdir(parents=True, exist_ok=True)
            if not destination.is_file() or destination.read_bytes() != path.read_bytes():
                shutil.copy(path, destination)
    # The host header, and the engine contract the binding implements: the C
    # ABI it registers through and the generated C++ codec.
    headers = [host / "Apple/CrestChromiumHost.h"] + [repo / "CrestContracts/include" / name for name in ENGINE_CONTRACT]
    for header in headers:
        destination = source / "chrome/browser/ui/crest" / header.name
        if not destination.is_file() or destination.read_bytes() != header.read_bytes():
            shutil.copy(header, destination)
    print("Installed host sources. Regenerate GN and build before packaging the native UI framework.")


if __name__ == "__main__":
    main()
