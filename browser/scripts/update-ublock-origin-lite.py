#!/usr/bin/env python3
"""Vendor an official Safari release with Complete mode, Spanish rules and a startup handshake."""

import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request
import zipfile


STARTUP = """const runtime = self.browser.runtime;
try {
    const { starting } = await runtime.sendNativeMessage('com.itsbrowser', { event: 'prepare' });
    if ( typeof starting !== 'boolean' ) { throw new Error('Content blocking preparation failed'); }
    self.browserStartingBlocker = starting;
    await import('./background.js');
} catch ( reason ) {
    runtime.sendNativeMessage('com.itsbrowser', { event: 'error', message: String(reason) }).catch(() => {});
}
"""


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError(f"Upstream WebKit adaptation needs review near {before!r}")
    return source.replace(before, after)


def patch_background(background):
    bootstrap = "async function start() {\n    await loadRulesetConfig();"
    background = replace_once(background, bootstrap, bootstrap + """
    if ( self.browserStartingBlocker ) { process.wakeupRun = false; }
    const browserRulesets = rulesetConfig.enabledRulesets.filter(id => id !== 'spa-1');
    if ( browserRulesets.includes('spa-0') === false ) { browserRulesets.push('spa-0'); }
    if ( JSON.stringify(browserRulesets) !== JSON.stringify(rulesetConfig.enabledRulesets) || rulesetConfig.strictBlockMode !== false ) {
        rulesetConfig.enabledRulesets = browserRulesets;
        rulesetConfig.strictBlockMode = false;
        await saveRulesetConfig();
    }
""")
    background = replace_once(
        background,
        "        enabledRulesets,\n    } = await enableRulesets(rulesetConfig.enabledRulesets);",
        """        enabledRulesets,
        error,
    } = await enableRulesets(rulesetConfig.enabledRulesets);
    if ( error ) { throw new Error(error); }""",
    )
    background = replace_once(
        background,
        """    if ( isNewVersion ) {
        updateDynamicAndSessionRules();
    } else {
        updateSessionRules();
    }""",
        """    if ( !stockUpdated ) {
        const result = await (isNewVersion ? updateDynamicAndSessionRules() : updateSessionRules());
        if ( result?.error ) { throw new Error(result.error); }
        if ( result === undefined ) {
            const ids = await dnr.getEnabledRulesets();
            if ( ids.length !== 0 ) {
                await dnr.updateEnabledRulesets({
                    enableRulesetIds: ids,
                    disableRulesetIds: ids,
                });
            }
        }
    }""",
    )
    background = replace_once(
        background,
        "const isFullyInitialized = start().then(( ) => {",
        """const isFullyInitialized = start().then(async () => {
    if ( await getDefaultFilteringMode() !== 3 ) {
        await setDefaultFilteringMode(3);
        await registerContentScripts();
    }
    browser.runtime.sendNativeMessage('com.itsbrowser', { event: 'ready' }).catch(() => {});""",
    )
    return replace_once(
        background,
        "}).catch(reason => {\n    ubolErr(reason);",
        """}).catch(reason => {
    browser.runtime.sendNativeMessage('com.itsbrowser', { event: 'error', message: String(reason) }).catch(() => {});
    ubolErr(reason);""",
    )


def package(archive):
    source = zipfile.ZipFile(io.BytesIO(archive))
    manifest = json.loads(source.read("manifest.json"))
    manifest["permissions"].append("nativeMessaging")
    if manifest["background"]["scripts"] != ["/js/background.js"]:
        raise ValueError("Upstream background entry point changed")
    manifest["background"]["scripts"] = ["/js/browser-startup.js"]
    spanish = next(rule for rule in manifest["declarative_net_request"]["rule_resources"] if rule["id"] == "spa-0")
    spanish["enabled"] = True

    replacements = {
        "manifest.json": (json.dumps(manifest, indent=2) + "\n").encode(),
        "js/background.js": patch_background(source.read("js/background.js").decode()).encode(),
        "js/ext.js": replace_once(
            source.read("js/ext.js").decode(),
            "if ( extURL.startsWith('safari-web-extension:') ) { return 'safari'; }",
            "if ( extURL.startsWith('safari-web-extension:') || extURL.startsWith('webkit-extension:') ) { return 'safari'; }",
        ).encode(),
        "js/mode-manager.js": replace_once(
            source.read("js/mode-manager.js").decode(),
            "    optimal: [ 'all-urls' ],\n    complete: [],",
            "    optimal: [],\n    complete: [ 'all-urls' ],",
        ).encode(),
        "js/ruleset-manager.js": replace_once(
            source.read("js/ruleset-manager.js").decode(),
            "        if ( ruleset.group === 'imported' ) { continue; }",
            "        if ( ruleset.group === 'imported' || ruleset.id === 'spa-1' ) { continue; }",
        ).encode(),
    }
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for entry in source.infolist():
            target.writestr(entry, replacements.get(entry.filename, source.read(entry.filename)))
        startup = zipfile.ZipInfo("js/browser-startup.js", source.getinfo("js/background.js").date_time)
        target.writestr(startup, STARTUP, compress_type=zipfile.ZIP_DEFLATED)
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
        "changes": "Recognize WebKit's extension scheme as the Safari runtime, default to Complete filtering and EasyList Spanish (spa-0), exclude Spanish/Portuguese (spa-1), and apply rules once during startup before notifying Browser. Filter lists match the upstream release.",
    }
    (resources / "uBlockOriginLite.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Bundled uBlock Origin Lite {version}")


if __name__ == "__main__":
    main()
