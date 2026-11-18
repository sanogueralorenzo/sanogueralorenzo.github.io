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
    const { starting, cachedRulesets } = await runtime.sendNativeMessage('com.itsbrowser', { event: 'prepare' });
    if ( typeof starting !== 'boolean' ) { throw new Error('Content blocking preparation failed'); }
    self.browserStartingBlocker = starting;
    self.browserCachedRulesets = cachedRulesets;
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
    background = replace_once(background, bootstrap, """async function start() {
    if ( self.browserCachedRulesets ) {
        rulesetConfig.enabledRulesets = self.browserCachedRulesets;
        rulesetConfig.strictBlockMode = false;
        await registerContentScripts();
        return;
    }
    await loadRulesetConfig();
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
    const scripts = await getRegisteredContentScripts();
    if ( self.browserCachedRulesets && scripts.includes('css-generic-all') === false ) {
        throw new Error('Complete filtering scripts could not be registered');
    }
    const snapshot = await browserCacheableRulesets(scripts);
    await runtime.sendNativeMessage('com.itsbrowser', { event: 'ready', snapshot });""",
    )
    background = replace_once(
        background,
        "}).catch(reason => {\n    ubolErr(reason);",
        """}).catch(reason => {
    browser.runtime.sendNativeMessage('com.itsbrowser', { event: 'error', message: String(reason) }).catch(() => {});
    ubolErr(reason);""",
    )
    return background + """

async function browserCacheableRulesets(scripts) {
    if ( self.browserCachedRulesets || scripts.includes('css-generic-all') === false ||
         rulesetConfig.popupBlockMode !== true || rulesetConfig.developerMode ) { return ''; }
    const [ modes, ids, imported, custom, sandbox, userRules ] = await Promise.all([
        getFilteringModeDetails(), dnr.getEnabledRulesets(), getImportedLists(),
        getAllCustomFilters(), getSandboxFilters(), getEffectiveUserRules(),
    ]);
    if ( modes.complete.size !== 1 || !modes.complete.has('all-urls') ||
         modes.none.size || modes.basic.size || modes.optimal.size ||
         imported.length || custom.length || sandbox || userRules.length || !ids.length ) { return ''; }
    return JSON.stringify(ids);
}

if ( !self.browserCachedRulesets ) {
    browser.storage.onChanged.addListener((changes, area) => {
        if ( area !== 'local' || !Object.keys(changes).some(key =>
            key === 'rulesetConfig' || key === 'filteringModeDetails' || key === 'sandboxFilters' ||
            key.startsWith('site.') || key.startsWith('rulesets.imported')) ) { return; }
        runtime.sendNativeMessage('com.itsbrowser', { event: 'invalidate' }).catch(() => {});
    });
}
"""


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
        "js/mode-manager.js": replace_once(replace_once(
            source.read("js/mode-manager.js").decode(),
            "    optimal: [ 'all-urls' ],\n    complete: [],",
            "    optimal: [],\n    complete: [ 'all-urls' ],",
        ), "    filteringModesToDNR(userModes);", "    if ( !self.browserCachedRulesets ) { filteringModesToDNR(userModes); }").encode(),
        "js/ruleset-manager.js": replace_once(replace_once(
            source.read("js/ruleset-manager.js").decode(),
            "        if ( ruleset.group === 'imported' ) { continue; }",
            "        if ( ruleset.group === 'imported' || ruleset.id === 'spa-1' ) { continue; }",
        ), "export async function getEnabledRulesets() {", """export async function getEnabledRulesets() {
    if ( self.browserCachedRulesets ) { return self.browserCachedRulesets; }""").encode(),
        "js/ext-compat.js": replace_once(
            source.read("js/ext-compat.js").decode(),
            "async function forceEnableRulesets(windowId) {",
            """async function forceEnableRulesets(windowId) {
    if ( self.browserCachedRulesets ) { return; }""",
        ).encode(),
    }
    cached_manifest = dict(manifest)
    del cached_manifest["declarative_net_request"]
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for entry in source.infolist():
            target.writestr(entry, replacements.get(entry.filename, source.read(entry.filename)))
        startup = zipfile.ZipInfo("js/browser-startup.js", source.getinfo("js/background.js").date_time)
        target.writestr(startup, STARTUP, compress_type=zipfile.ZIP_DEFLATED)
        target.writestr("manifest-cached.json", json.dumps(cached_manifest, indent=2) + "\n")
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
        "changes": "Recognize WebKit's extension scheme, use Complete filtering and EasyList Spanish, and support Browser's precompiled rules and startup handshake. Filter lists match the upstream release.",
    }
    (resources / "uBlockOriginLite.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Bundled uBlock Origin Lite {version}")


if __name__ == "__main__":
    main()
