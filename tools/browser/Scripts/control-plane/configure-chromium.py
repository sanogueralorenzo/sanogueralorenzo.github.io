#!/usr/bin/env python3
"""Select a reproducible configuration in an existing, idle Chromium output."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--configuration", required=True, choices=["development", "performance"])
    parser.add_argument("--sdk", type=Path, help="Compatible macOS SDK; required for performance builds")
    parser.add_argument("--pgo-profile", type=Path, help="Pinned mac-arm profile; required for performance builds")
    args = parser.parse_args()
    source = args.source.resolve()
    if source == REPO or REPO in source.parents:
        parser.error("Chromium sources and products must be outside Crest")
    output = source / "out/CrestBaseline"
    arguments = output / "args.gn"
    gn = output / "gn"
    if not arguments.is_file() or not gn.is_file():
        parser.error("Prepare the pinned source before configuring it")
    lock = json.loads((REPO / "CrestEngines/Chromium/source.lock.json").read_text())
    settings = dict(lock[f"{args.configuration}BuildArguments"])
    if args.configuration == "performance":
        if args.sdk is None or args.pgo_profile is None:
            parser.error("Performance builds require --sdk and --pgo-profile")
        sdk = args.sdk.resolve()
        profile = args.pgo_profile.resolve()
        sdk_settings = sdk / "SDKSettings.json"
        if not sdk_settings.is_file() or not profile.is_file():
            parser.error("SDK or PGO profile is missing")
        expected = lock["performanceInputs"]
        if json.loads(sdk_settings.read_text())["Version"] != expected["macSDKVersion"]:
            parser.error(f"Use the compatible macOS {expected['macSDKVersion']} SDK")
        profile_name = (source / "chrome/build/mac-arm.pgo.txt").read_text().strip()
        if profile_name != expected["pgoProfile"] or profile.name != profile_name:
            parser.error("PGO profile does not match the pinned Chromium source")
        with profile.open("rb") as stream:
            checksum = hashlib.file_digest(stream, "sha256").hexdigest()
        if checksum != expected["pgoSHA256"]:
            parser.error("PGO profile checksum does not match the lock")
        if not (source / "v8/tools/builtins-pgo/profiles/x64.profile").is_file():
            parser.error("V8 builtin optimization profile is missing")
        # Chromium declares SDK inputs as generated outputs, so its SDK alias
        # must live beneath root_build_dir, just like sdk_info.py's aliases.
        sdk_link = output / "sdk/crest" / sdk.name
        if sdk_link.exists() or sdk_link.is_symlink():
            if not sdk_link.is_symlink() or sdk_link.resolve() != sdk:
                parser.error(f"SDK alias already belongs to another path: {sdk_link}")
        else:
            sdk_link.parent.mkdir(parents=True, exist_ok=True)
            sdk_link.symlink_to(sdk, target_is_directory=True)
        settings.update(mac_sdk_path=f"//{sdk_link.relative_to(source).as_posix()}",
                        pgo_data_path=str(profile))
    elif args.sdk or args.pgo_profile:
        parser.error("--sdk and --pgo-profile apply only to performance builds")

    # Replace only preset-owned scalar arguments, including prior duplicates.
    # Keep independent downstream flags such as the native-host integration.
    owned = set(lock["developmentBuildArguments"]) | set(lock["performanceBuildArguments"])
    owned.update(["mac_sdk_path", "pgo_data_path"])
    previous = arguments.read_text()
    retained = []
    for line in previous.splitlines():
        assignment = re.match(r"\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*=", line)
        if assignment is None or assignment[1] not in owned:
            retained.append(line)
    configured = "\n".join(retained).rstrip() + "\n\n"
    configured += "\n".join(f"{key}={json.dumps(value)}" for key, value in settings.items()) + "\n"
    arguments.write_text(configured)
    command = [str(gn), "gen", "out/CrestBaseline", "--fail-on-unused-args"]
    try:
        subprocess.run(command, cwd=source, check=True)
    except subprocess.CalledProcessError:
        arguments.write_text(previous)
        subprocess.run(command, cwd=source, check=True)
        raise
    print(f"Configured {args.configuration}; rebuild chrome in the same output directory.")


if __name__ == "__main__":
    main()
