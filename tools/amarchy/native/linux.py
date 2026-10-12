#!/usr/bin/env python3
"""Compile the small Linux desktop adapter against the locked guest's glibc."""
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
glibc = next(p for p in lock["packages"] if p["name"] == "glibc")
archive = project / "app/build/runtime-packages" / (glibc["sha256"] + ".archive")
with archive.open("rb") as source:
    if hashlib.file_digest(source, "sha256").hexdigest() != glibc["sha256"] or archive.stat().st_size != glibc["bytes"]:
        raise ValueError("The locked glibc archive failed verification")
with tarfile.open(archive) as tar:
    tar.extractall(sysroot, members=(member for member in tar if member.name.startswith(("usr/include/", "usr/lib/"))), filter="data")
ndk = Path(os.environ["NDK"])
host = "darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64"
tools = ndk / "toolchains/llvm/prebuilt" / host
compiler = tools / "bin/clang"
library = sysroot / "usr/lib"
resource = subprocess.check_output([compiler, "-print-resource-dir"], text=True).strip()
subprocess.run([compiler, "--target=aarch64-linux-gnu", f"--sysroot={sysroot}",
    "-isystem", str(sysroot / "usr/include"),
    "-isystem", str(tools / "sysroot/usr/include/aarch64-linux-android"),
    "-isystem", str(tools / "sysroot/usr/include"),
    "-O2", "-fPIC", "-fuse-ld=lld", "-nostdlib", "-shared",
    str(library / "crti.o"), str(HERE / "desktop_memory.c"),
    str(Path(resource) / "lib/linux/libclang_rt.builtins-aarch64-android.a"),
    str(library / "libc.so.6"), str(library / "libc_nonshared.a"), str(library / "crtn.o"),
    "-Wl,-soname,libamarchy-memory.so", "-Wl,-z,max-page-size=16384",
    "-o", str(output / "libamarchy-memory.so")], check=True)
