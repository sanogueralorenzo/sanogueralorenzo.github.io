#!/usr/bin/env python3
"""Build the native core for an Xcode target, reusing that build's derived data."""

import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    repo = Path(__file__).resolve().parents[2]
    platform = os.environ["PLATFORM_NAME"]
    runtimes = {"macosx": "osx-arm64", "iphoneos": "ios-arm64", "iphonesimulator": "iossimulator-arm64"}
    if platform not in runtimes or os.environ.get("ARCHS", "arm64").split() != ["arm64"]:
        raise RuntimeError("The Crest core currently supports Apple silicon macOS and arm64 iOS/device Simulator builds")
    default = Path(os.environ["BUILT_PRODUCTS_DIR"]) / "CrestCore"
    key = "CREST_CORE_LIBRARY_DIR" if platform == "macosx" else "CREST_CORE_FRAMEWORK_DIR"
    output = Path(os.environ[key]).resolve()
    product = output / ("CrestCore.Native.dylib" if platform == "macosx" else "CrestCoreABI.framework/CrestCoreABI")
    if output != default.resolve():
        if not product.is_file():
            raise RuntimeError(f"Explicit {key} has no core library: {product}")
        print(f"Using explicitly supplied core: {product}")
        return
    candidates = [os.environ.get("CREST_DOTNET"), shutil.which("dotnet"),
                  str(Path.home() / ".dotnet/dotnet"), "/usr/local/share/dotnet/dotnet"]
    dotnet = next((p for p in candidates if p and Path(p).is_file()), None)
    if not dotnet:
        raise RuntimeError("Install the SDK in CrestCore/global.json, or run Scripts/control-plane/install-dotnet.sh")
    core = repo / "CrestCore"
    # MSBuild imports environment names case-insensitively as project properties.
    # Xcode's TARGETNAME otherwise renames every referenced assembly to Crest.
    inherited = {"PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "DEVELOPER_DIR",
                 "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy"}
    environment = {k: v for k, v in os.environ.items()
                   if k in inherited or k.startswith(("DOTNET_", "NUGET_", "LC_"))}
    environment["SDKROOT"] = subprocess.check_output(
        ["xcrun", "--sdk", platform, "--show-sdk-path"], text=True).strip()
    version = subprocess.check_output([dotnet, "--version"], cwd=core, env=environment, text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", platform, "--show-sdk-version"], text=True).strip()
    inputs = [p for folder in ("src", "tools") for p in (core / folder).rglob("*") if p.is_file()
              and not {"bin", "obj"}.intersection(p.relative_to(core).parts)]
    inputs += list((repo / "CrestShared/Infrastructure/Core/Generated").glob("*.swift"))
    inputs += list(core.glob("Directory.*")) + [core / "global.json", Path(__file__).resolve(),
                                               repo / "Scripts/control-plane/package-apple-core.py"]
    digest = hashlib.sha256(f"{version}:{platform}:{sdk}:{os.environ.get('DEVELOPER_DIR', '')}".encode())
    for path in sorted(inputs):
        digest.update(str(path.relative_to(repo)).encode())
        digest.update(path.read_bytes())
    # A Debug app's core runs the core's cross-checks, which Release builds leave out.
    cross_checks = os.environ.get("CONFIGURATION") == "Debug"
    digest.update(f"cross-checks:{cross_checks}".encode())
    fingerprint = digest.hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    # App and framework targets can request the same core in a parallel build.
    with (output / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = output / ".source-hash"
        if product.is_file() and stamp.exists() and stamp.read_text() == fingerprint:
            print(f"Crest core is current ({runtimes[platform]}, SDK {version})")
            return
        # The Swift models and codecs are generated from the same contract
        # records; a stale copy would misread the core, so refuse to build.
        subprocess.run([dotnet, "run", "--project", "tools/CrestCore.Generator", "--nologo", "--",
                        "--check", "--root", str(repo)], cwd=core, env=environment, check=True)
        publish = output / "publish"
        command = [dotnet, "publish", "src/CrestCore.Native", "-c", "Release", "-r", runtimes[platform],
                   "--artifacts-path", str(output / "intermediates"), "-o", str(publish), "--nologo",
                   f"-p:CrestCrossChecks={'true' if cross_checks else 'false'}"]
        if platform != "macosx":
            command += ["-p:PublishAotUsingRuntimePack=true"]
        subprocess.run(command, cwd=core, env=environment, check=True)
        if platform == "macosx":
            shutil.copy2(publish / "CrestCore.Native.dylib", product.with_suffix(".pending"))
            product.with_suffix(".pending").replace(product)
        else:
            framework = output / "CrestCoreABI.framework"
            if framework.exists():
                shutil.rmtree(framework)
            subprocess.run([sys.executable, str(repo / "Scripts/control-plane/package-apple-core.py"),
                            "--library", str(publish / "CrestCore.Native.dylib"), "--output", str(framework),
                            "--platform", platform], check=True)
        stamp.write_text(fingerprint)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: Crest core build failed: {error}")
