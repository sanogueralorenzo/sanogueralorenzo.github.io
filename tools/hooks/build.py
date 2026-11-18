"""Build and atomically install the shared bridge in private application data."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def build(home, checkout):
    if not shutil.which("cargo"):
        raise ValueError(
            "Install Rust/Cargo and a C compiler, then run browser-hooks setup."
        )
    target = home / "build/bridge"
    target.mkdir(parents=True, exist_ok=True, mode=0o700)
    log = home / "build/bridge-build.log"
    with log.open("w") as output:
        result = subprocess.run(
            [
                "cargo",
                "build",
                "--locked",
                "--release",
                "--manifest-path",
                str(checkout / "bridge/Cargo.toml"),
            ],
            env={**os.environ, "CARGO_TARGET_DIR": str(target)},
            stdout=output,
            stderr=subprocess.STDOUT,
        )
    if result.returncode:
        raise RuntimeError(
            f"Rust bridge build failed. Check {log}; install Rust/Cargo and a C compiler."
        )
    folder = home / "bin"
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    binary = folder / "browser-hooks-bridge"
    with tempfile.NamedTemporaryFile(dir=folder, delete=False) as file:
        staged = Path(file.name)
    try:
        shutil.copyfile(target / "release/browser-hooks-bridge", staged)
        staged.chmod(0o700)
        os.replace(staged, binary)
    finally:
        staged.unlink(missing_ok=True)
    return binary
