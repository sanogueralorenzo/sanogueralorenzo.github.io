#!/usr/bin/env python3
"""Package an already published NativeAOT iOS library as an embeddable framework."""

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--platform", choices=["iphoneos", "iphonesimulator"], required=True)
    args = parser.parse_args()
    if not args.library.is_file() or not args.output.is_absolute() or args.output.exists():
        parser.error("Provide a published library and a new absolute output framework path")
    if args.output.name != "CrestCoreABI.framework":
        parser.error("The output must be named CrestCoreABI.framework")
    args.output.mkdir(parents=True)
    binary = args.output / "CrestCoreABI"
    shutil.copy2(args.library, binary)
    subprocess.run(["xcrun", "install_name_tool", "-id", "@rpath/CrestCoreABI.framework/CrestCoreABI", str(binary)], check=True)
    info = {
        "CFBundleExecutable": "CrestCoreABI", "CFBundleName": "CrestCoreABI",
        "CFBundleIdentifier": "com.pauldavis.crest.control-plane.core",
        "CFBundlePackageType": "FMWK", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "26.1",
        "CFBundleSupportedPlatforms": ["iPhoneOS" if args.platform == "iphoneos" else "iPhoneSimulator"],
    }
    (args.output / "Info.plist").write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    main()
