#!/usr/bin/env python3
"""Verify the pinned upstream checkout and prepare a new Chromium source directory."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import zipfile

REPO = Path(__file__).resolve().parents[2]
ENGINE = REPO / "CrestEngines/Chromium"


def run(args, cwd):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", required=True, type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    upstream = args.upstream.resolve()
    if upstream == REPO or REPO in upstream.parents:
        parser.error("The upstream checkout must be outside Crest")
    lock = json.loads((ENGINE / "source.lock.json").read_text())
    for root, expected in [(upstream, lock["ungoogledMac"]["commit"]),
                           (upstream / "ungoogled-chromium", lock["ungoogled"]["commit"])]:
        actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        if actual != expected:
            parser.error(f"Unexpected upstream revision in {root.name}")
    for relative, expected in {**lock["inputs"], **lock["patches"]}.items():
        if digest(upstream / relative) != expected:
            parser.error(f"Upstream input changed: {relative}")
    for relative, expected in lock["crestPatches"].items():
        if digest(ENGINE / relative) != expected:
            parser.error(f"Crest patch changed: {relative}")
    if args.verify_only:
        print("Pinned source inputs and patch digests match.")
        return
    source = upstream / "build/src"
    if source.exists():
        parser.error("Source directory already exists; use --verify-only or a new upstream checkout")
    python = sys.executable
    utils = upstream / "ungoogled-chromium/utils"
    retrieve = upstream / "retrieve_and_unpack_resource.py"
    run([python, retrieve, "--download", "--generic", "arm64"], upstream)
    archive = upstream / "build/download_cache" / Path(lock["chromium"]["sourceArchive"]).name
    if digest(archive) != lock["chromium"]["sourceArchiveSha256"]:
        parser.error("Chromium source archive does not match the Crest lock")
    run([python, utils / "prune_binaries.py", source, upstream / "ungoogled-chromium/pruning.list"], upstream)
    run([python, utils / "patches.py", "apply", source, upstream / "ungoogled-chromium/patches", upstream / "patches"], upstream)
    run([python, utils / "domain_substitution.py", "apply", "-r", upstream / "ungoogled-chromium/domain_regex.list",
         "-f", upstream / "ungoogled-chromium/domain_substitution.list", source], upstream)
    run([python, retrieve, "--platform-specific", "arm64"], upstream)
    for relative in lock["crestPatches"]:
        run(["patch", "-p1", "--forward", "--input", ENGINE / relative], source)

    # The pinned Rust archive omits the loader-relative LLVM alias used by rust-objcopy.
    rust = source / "third_party/rust-toolchain/rustc"
    llvm = rust / "lib/libLLVM.dylib"
    alias = rust / "lib/rustlib/aarch64-apple-darwin/lib/libLLVM.dylib"
    if not alias.exists():
        alias.symlink_to(os.path.relpath(llvm, alias.parent.resolve()))

    # Chromium fetches these host tools from CIPD. The source archive omits
    # them, and ungoogled points the build at Homebrew; Crest pins Chromium's
    # own packages instead.
    tools = (("esbuild", "third_party/devtools-frontend/src/third_party/esbuild", "esbuild"),
             ("typescript", "third_party/typescript/mac-arm64/src", "lib/tsc"))
    for name, relative, executable in tools:
        package = lock[name]
        download = upstream / f"build/download_cache/crest-{name}.zip"
        urllib.request.urlretrieve(package["url"], download)
        if digest(download) != package["sha256"]:
            parser.error(f"{name} archive digest does not match the lock")
        destination = source / relative
        with zipfile.ZipFile(download) as archive:
            for item in archive.infolist():
                resolved = (destination / item.filename).resolve()
                if destination.resolve() not in resolved.parents:
                    parser.error(f"Invalid {name} archive member")
            archive.extractall(destination)
        (destination / executable).chmod(0o755)
    output = source / "out/CrestBaseline"
    output.mkdir(parents=True, exist_ok=True)
    flags = (upstream / "ungoogled-chromium/flags.gn").read_text() + "\n" + (upstream / "flags.macos.gn").read_text()
    for key, value in lock["developmentBuildArguments"].items():
        flags += f"\n{key}={json.dumps(value)}"
    (output / "args.gn").write_text(flags + "\n")
    run([python, source / "tools/gn/bootstrap/bootstrap.py", "-o", "out/CrestBaseline/gn", "--skip-generate-buildfiles"], source)
    # Checks out the bindgen revision the script pins, as upstream's build does.
    run([python, source / "tools/rust/build_bindgen.py", "--skip-test"], source)
    run([output / "gn", "gen", "out/CrestBaseline", "--fail-on-unused-args"], source)
    print("Source prepared. Run build-chromium-baseline.py against build/src.")


if __name__ == "__main__":
    main()
