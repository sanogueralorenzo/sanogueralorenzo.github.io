#!/usr/bin/env python3
"""Vendor an official Safari release with Complete filtering and a startup handshake."""

import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request
import zipfile


def package(archive):
    source = zipfile.ZipFile(io.BytesIO(archive))
    manifest = json.loads(source.read("manifest.json"))
    manifest["permissions"].append("nativeMessaging")
    background = source.read("js/background.js").decode()
    success = "const isFullyInitialized = start().then(( ) => {"
    failure = "}).catch(reason => {\n    ubolErr(reason);"
    if background.count(success) != 1 or background.count(failure) != 1:
        raise ValueError("Upstream startup changed; review the Lean handshake before updating")
    background = background.replace(success, "const isFullyInitialized = start().then(async () => {\n" +
        "    if ( await getDefaultFilteringMode() !== 3 ) {\n" +
        "        await setDefaultFilteringMode(3); // Lean uses uBOL Complete filtering.\n" +
        "        await registerContentScripts();\n" +
        "    }\n" +
        "    browser.runtime.sendNativeMessage('dev.leanbrowser', { event: 'ready' }).catch(() => {});")
    background = background.replace(failure, "}).catch(reason => {\n" +
        "    browser.runtime.sendNativeMessage('dev.leanbrowser', { event: 'error', message: String(reason) }).catch(() => {});\n" +
        "    ubolErr(reason);")
    replacements = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "js/background.js": background.encode(),
    }
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for entry in source.infolist():
            target.writestr(entry, replacements.get(entry.filename, source.read(entry.filename)))
    return output.getvalue()


def main():
    version = sys.argv[1]
    release_url = f"https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/tags/{version}"
    with urllib.request.urlopen(release_url) as response:
        release = json.load(response)
    name = f"uBOLite_{version}.safari.zip"
    asset = next(item for item in release["assets"] if item["name"] == name)
    with urllib.request.urlopen(asset["browser_download_url"]) as response:
        archive = response.read()
    digest = "sha256:" + hashlib.sha256(archive).hexdigest()
    if asset.get("digest") != digest:
        raise ValueError("Release archive does not match GitHub's published SHA-256")
    bundled = package(archive)
    resources = Path(__file__).resolve().parents[1] / "Resources"
    (resources / "uBlockOriginLite.zip").write_bytes(bundled)
    metadata = {
        "version": version,
        "source": release["html_url"],
        "archive": asset["browser_download_url"],
        "upstreamSHA256": digest.removeprefix("sha256:"),
        "bundledSHA256": hashlib.sha256(bundled).hexdigest(),
        "changes": "Enabled Complete filtering and added nativeMessaging success/error startup messages to Lean; filtering algorithms and rules are unchanged.",
    }
    (resources / "uBlockOriginLite.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Bundled uBlock Origin Lite {version}")


if __name__ == "__main__":
    main()
