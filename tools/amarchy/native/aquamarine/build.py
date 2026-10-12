#!/usr/bin/env python3
"""Rebuild the pinned Aquamarine ABI with the demonstrated configure-order fix."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent.parent


def download(entry, cache):
    path = cache / (entry["sha256"] + ".archive")
    if not path.exists():
        temporary = path.with_suffix(".partial")
        with urllib.request.urlopen(entry["url"], timeout=120) as response, temporary.open("wb") as output:
            while block := response.read(1024 * 1024):
                output.write(block)
        temporary.replace(path)
    with path.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != entry["sha256"] or path.stat().st_size != entry["bytes"]:
            raise ValueError(f"Verification failed: {entry['name']}")
    return path


def source_archive(path, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(path) as archive:
        for member in archive:
            member.name = member.name.split("/", 1)[-1]
            if member.name:
                archive.extract(member, destination, filter="data")


def sdk_members(archive):
    for member in archive:
        name = member.name
        selected = name.startswith("usr/include/") or (
            name.startswith("usr/lib/") and (name.endswith((".so", ".o")) or ".so." in name)) or name.startswith(("usr/share/wayland", "usr/share/hwdata/"))
        if not selected:
            continue
        if member.issym() and member.linkname.startswith("/"):
            member.linkname = os.path.relpath(member.linkname.lstrip("/"), str(Path(name).parent))
        yield member


def main():
    output = Path(sys.argv[1]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    build = output.parent.parent.parent / "aquamarine-build"
    build.mkdir(exist_ok=True)
    cache = build / "packages"
    cache.mkdir(exist_ok=True)
    sdk = build / "sdk"
    sdk.mkdir(exist_ok=True)
    inputs = json.loads((HERE / "sources.lock.json").read_text())
    paths = {entry["name"]: download(entry, cache) for entry in inputs}
    for name in ["aquamarine", "hyprwayland-scanner", "pugixml"]:
        source_archive(paths[name], build / name)
    with tarfile.open(paths["gcc-headers"]) as archive:
        archive.extractall(sdk, members=(m for m in archive if m.name.startswith("usr/include/") or m.name.endswith(("/crtbeginS.o", "/crtendS.o"))), filter="data")
    for name in ["systemd", "hwdata"]:
        with tarfile.open(paths[name]) as archive:
            archive.extractall(sdk, members=sdk_members(archive), filter="data")
    lock = json.loads((PROJECT / "runtime/packages.lock.json").read_text())
    dependencies = ["glibc", "libdrm", "libglvnd", "mesa", "seatd", "libinput", "hyprutils", "pixman", "systemd-libs", "libdisplay-info", "wayland", "wayland-protocols", "libstdc++", "libgcc"]
    for name in dependencies:
        entry = next(e for e in lock["packages"] if e["name"] == name)
        path = PROJECT / "app/build/runtime-packages" / (entry["sha256"] + ".archive")
        with path.open("rb") as source:
            if hashlib.file_digest(source, "sha256").hexdigest() != entry["sha256"]:
                raise ValueError(f"Verification failed: {name}")
        with tarfile.open(path) as archive:
            archive.extractall(sdk, members=sdk_members(archive), filter="data")
    scanner = build / "scanner"
    scanner_source = build / "hyprwayland-scanner"
    pugixml = build / "pugixml/src"
    subprocess.run(["c++", "-std=c++23", "-O2", '-DSCANNER_VERSION="0.4.5"', f"-I{pugixml}",
        *map(str, sorted((scanner_source / "src").glob("*.cpp"))), str(pugixml / "pugixml.cpp"), "-o", str(scanner)], check=True)
    source = build / "aquamarine"
    subprocess.run(["patch", "-p1", "-F0", "-i", str(HERE / "configure-before-frame.patch")], cwd=source, check=True)
    protocols = source / "protocols"
    protocols.mkdir(exist_ok=True)
    for xml, flags in [
        (sdk / "usr/share/wayland/wayland.xml", ["--wayland-enums", "--client"]),
        (sdk / "usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml", ["--client"]),
        (sdk / "usr/share/wayland-protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml", ["--client"]),
    ]:
        subprocess.run([scanner, *flags, xml, protocols], check=True)
    with (sdk / "usr/share/hwdata/pnp.ids").open("rb") as ids:
        pnp = subprocess.check_output(["sh", str(source / "data/hwdata.sh")], stdin=ids, text=True)
    (build / "hwdata.hpp").write_text((source / "data/hwdata.hpp.in").read_text().replace("@HWDATA_PNP_IDS@", pnp))
    host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
    toolchain = Path(os.environ["NDK"]) / "toolchains/llvm/prebuilt" / host
    compiler = toolchain / "bin/clang++"
    headers = next((sdk / "usr/include/c++").iterdir())
    library = sdk / "usr/lib"
    flags = [compiler, "--target=aarch64-linux-gnu", f"--sysroot={sdk}", "-std=c++23", "-O2", "-fPIC", "-mno-outline-atomics", "-nostdinc++",
        f"-ffile-prefix-map={build}=.", '-DAQUAMARINE_VERSION="0.15.1"', "-DAQUAMARINE_HAS_LIBINPUT_PLUGINS",
        "-isystem", str(headers), "-isystem", str(headers / "aarch64-unknown-linux-gnu"), "-isystem", str(headers / "backward"),
        "-isystem", str(sdk / "usr/include"), "-isystem", str(toolchain / "sysroot/usr/include/aarch64-linux-android"), "-isystem", str(toolchain / "sysroot/usr/include"),
        f"-I{sdk}/usr/include/libdrm", f"-I{sdk}/usr/include/pixman-1", f"-I{source}/include", f"-I{source}/src", f"-I{source}/src/include", f"-I{protocols}", f"-I{build}"]
    sources = sorted((source / "src").rglob("*.cpp")) + sorted(protocols.glob("*.cpp"))
    objects = build / "objects"
    objects.mkdir(exist_ok=True)
    def compile_source(path):
        object_path = objects / (str(path.relative_to(source)).replace("/", "_") + ".o")
        subprocess.run(flags + ["-c", str(path), "-o", str(object_path)], check=True)
        return object_path
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        compiled = list(executor.map(compile_source, sources))
    libraries = ["libEGL.so.1", "libGL.so.1", "libseat.so.1", "libinput.so.10", "libwayland-client.so.0", "libhyprutils.so", "libpixman-1.so.0",
        "libdrm.so.2", "libgbm.so.1", "libudev.so.1", "libdisplay-info.so.3", "libstdc++.so.6", "libgcc_s.so.1", "libm.so.6", "libc.so.6"]
    gcc_library = next((sdk / "usr/lib/gcc/aarch64-unknown-linux-gnu").iterdir())
    resource = subprocess.check_output([compiler, "-print-resource-dir"], text=True).strip()
    subprocess.run([compiler, "--target=aarch64-linux-gnu", f"--sysroot={sdk}", "-fuse-ld=lld", "-nostdlib", "-shared", "-Wl,-z,max-page-size=16384", "-Wl,-soname,libaquamarine.so.14",
        str(library / "crti.o"), str(gcc_library / "crtbeginS.o"), *map(str, compiled),
        str(Path(resource) / "lib/linux/libclang_rt.builtins-aarch64-android.a"), *[str(library / name) for name in libraries],
        str(gcc_library / "crtendS.o"), str(library / "crtn.o"), "-o", str(output)], check=True)
    subprocess.run([toolchain / "bin/llvm-strip", "--strip-unneeded", output], check=True)
    print(f"Built {output.name}: {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
