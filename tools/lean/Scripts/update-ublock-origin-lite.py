#!/usr/bin/env python3
"""Vendor an official Safari release with Complete mode, Spanish rules and a startup handshake."""

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
    environment = source.read("js/ext.js").decode()
    safari_check = "if ( extURL.startsWith('safari-web-extension:') ) { return 'safari'; }"
    if environment.count(safari_check) != 1:
        raise ValueError("Upstream runtime detection changed; review the WebKit adaptation")
    environment = environment.replace(safari_check,
        "if ( extURL.startsWith('safari-web-extension:') || extURL.startsWith('webkit-extension:') ) { return 'safari'; }")
    success = "const isFullyInitialized = start().then(( ) => {"
    failure = "}).catch(reason => {\n    ubolErr(reason);"
    bootstrap = "async function start() {\n    await loadRulesetConfig();"
    if background.count(success) != 1 or background.count(failure) != 1 or background.count(bootstrap) != 1:
        raise ValueError("Upstream startup changed; review the Crest handshake before updating")
    background = background.replace(bootstrap, bootstrap + "\n" +
        "    const crestRulesets = rulesetConfig.enabledRulesets.filter(id => id !== 'spa-1');\n" +
        "    if ( crestRulesets.includes('spa-0') === false ) { crestRulesets.push('spa-0'); }\n" +
        "    if ( JSON.stringify(crestRulesets) !== JSON.stringify(rulesetConfig.enabledRulesets) || rulesetConfig.strictBlockMode !== false ) {\n" +
        "        rulesetConfig.enabledRulesets = crestRulesets;\n" +
        "        rulesetConfig.strictBlockMode = false; // Match the upstream Safari default.\n" +
        "        await saveRulesetConfig();\n" +
        "    }\n")
    background = background.replace(success, "const isFullyInitialized = start().then(async () => {\n" +
        "    if ( await getDefaultFilteringMode() !== 3 ) {\n" +
        "        await setDefaultFilteringMode(3); // Crest uses uBOL Complete filtering.\n" +
        "        await registerContentScripts();\n" +
        "    }\n" +
        "    browser.runtime.sendNativeMessage('com.pauldavis.crest', { event: 'ready' }).catch(() => {});")
    background = background.replace(failure, "}).catch(reason => {\n" +
        "    browser.runtime.sendNativeMessage('com.pauldavis.crest', { event: 'error', message: String(reason) }).catch(() => {});\n" +
        "    ubolErr(reason);")
    replacements = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "js/background.js": background.encode(),
        "js/ext.js": environment.encode(),
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
    resources = Path(__file__).resolve().parents[1] / "CrestShared" / "Resources"
    (resources / "uBlockOriginLite.zip").write_bytes(bundled)
    with zipfile.ZipFile(io.BytesIO(bundled)) as packaged:
        (resources / "uBlockOriginLite-LICENSE.txt").write_bytes(packaged.read("LICENSE.txt"))
    metadata = {
        "version": version,
        "source": release["html_url"],
        "archive": asset["browser_download_url"],
        "upstreamSHA256": digest.removeprefix("sha256:"),
        "bundledSHA256": hashlib.sha256(bundled).hexdigest(),
        "changes": "Recognize WebKit's extension scheme as the Safari runtime, enable Complete filtering and EasyList Spanish (spa-0), exclude Spanish/Portuguese (spa-1), and add nativeMessaging startup messages; filtering algorithms and rules are unchanged.",
    }
    (resources / "uBlockOriginLite.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Bundled uBlock Origin Lite {version}")


if __name__ == "__main__":
    main()
