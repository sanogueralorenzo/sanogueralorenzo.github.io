# Rebuild and update Arch

Builds consume the reviewed `native/runtime/packages.tsv`, repository hashes and source pins; they never resolve fresh dependencies. Run `python3 native/runtime/update.py` separately and review its changes. Mesa/Wayland versions and the build-only GCC version must match `native/runtime/mesa` pins; the build refuses a mismatch. Review and refresh those source checksums/tool inputs together when upstream changes.

Use NDK `28.2.13676358`, Python 3, Bison 3.8.2, Flex 2.6.4, Ninja, pkg-config, a host C compiler/Expat headers, XZ and archive tools. Install the pinned Python tools in an isolated environment:

```sh
python3 -m venv /tmp/androidsteam-mesa-tools
/tmp/androidsteam-mesa-tools/bin/pip install -r native/runtime/mesa/requirements.txt
NDK=/path/to/android/ndk/28.2.13676358 \
MESA_PYTHON=/tmp/androidsteam-mesa-tools/bin/python3 \
bash native/runtime/build.sh /path/to/output
```

The temporary filesystem must be case-sensitive. On macOS set `TMPDIR` to a case-sensitive APFS volume and put the pinned Bison/Ninja on `PATH`. Retain `output/packages` and `output/mesa`: every cached archive is checksum-checked, and rolling Arch mirrors may remove older packages. GCC development files and the Wayland scanner/protocol XML are build-host inputs, never runtime additions.

Build twice independently and compare archive bytes. Audit retained contents/dependency paths with `native/runtime/audit.py`; validate snapshot replacement/recovery, Steam and actual gameplay on the S24. Publish only a coherent tested snapshot at a new fixed release URL, then update `RuntimeInstaller`'s version, URL, size and SHA-256 together. The app validates staging before replacement and recovers an interrupted swap; Steam accounts, installed games, saves and settings remain in the separate home. Steam and ARM64 Proton use Valve's existing update mechanisms.
