#!/usr/bin/env python3
"""Compile Linux desktop adapters against the locked guest libraries and headers."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

HERE = Path(__file__).resolve().parent
project = HERE.parent
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
sysroot = output.parent.parent / "linux-sysroot"
sysroot.mkdir(exist_ok=True)
lock = json.loads((project / "runtime/packages.lock.json").read_text())
for name in ["glibc", "libdrm", "libglvnd", "mesa"]:
    package = next(p for p in lock["packages"] if p["name"] == name)
    archive = project / "app/build/runtime-packages" / (package["sha256"] + ".archive")
    with archive.open("rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != package["sha256"] or archive.stat().st_size != package["bytes"]:
            raise ValueError(f"The locked {name} archive failed verification")
    with tarfile.open(archive) as tar:
        tar.extractall(sysroot, members=(member for member in tar if member.name.startswith(("usr/include/", "usr/lib/"))), filter="data")
ndk = Path(os.environ["NDK"])
host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
tools = ndk / "toolchains/llvm/prebuilt" / host
compiler = tools / "bin/clang"
library = sysroot / "usr/lib"
resource = subprocess.check_output([compiler, "-print-resource-dir"], text=True).strip()
common = [compiler, "--target=aarch64-linux-gnu", f"--sysroot={sysroot}",
    "-isystem", str(sysroot / "usr/include"),
    "-isystem", str(sysroot / "usr/include/libdrm"),
    "-isystem", str(tools / "sysroot/usr/include/aarch64-linux-android"),
    "-isystem", str(tools / "sysroot/usr/include"),
    "-O2", "-fPIC", "-fuse-ld=lld", "-nostdlib", "-Wl,-z,max-page-size=16384"]
runtime = [
    str(Path(resource) / "lib/linux/libclang_rt.builtins-aarch64-android.a"),
    str(library / "libc.so.6"), str(library / "libc_nonshared.a"), str(library / "crtn.o"),
]
(output / "libamarchy-memory.so").unlink(missing_ok=True)
subprocess.run(common + ["-shared", str(library / "crti.o"), str(HERE / "software_drm.c")] + runtime +
    ["-Wl,-soname,libamarchy-software-drm.so", "-o", str(output / "libamarchy-software-drm.so")], check=True)
probe = output.parent.parent / "linux-probe/arm64-v8a"
probe.mkdir(parents=True, exist_ok=True)
subprocess.run(common + [str(library / "crt1.o"), str(library / "crti.o"), str(HERE / "egl_probe.c"),
    str(library / "libgbm.so.1"), str(library / "libEGL.so.1"), str(library / "libGLESv2.so.2"),
    "-Wl,--allow-shlib-undefined", "-Wl,--dynamic-linker=/lib/ld-linux-aarch64.so.1"] + runtime +
    ["-o", str(probe / "libamarchy-egl-probe.so")], check=True)
