import Foundation

enum BrowserContentExtensionPatches {
    static func apply(in directory: URL) throws {
        for (path, edits) in patches {
            try Task.checkCancellation()
            let file = directory.appendingPathComponent(path)
            var source = try String(contentsOf: file, encoding: .utf8)
            for (before, after) in edits {
                guard let match = source.range(of: before, options: .literal),
                    source.range(of: before, options: .literal, range: match.upperBound..<source.endIndex) == nil
                else { throw IncompatibleExtension(path: path) }
                source.replaceSubrange(match, with: after)
            }
            if path == "js/background.js" { source += backgroundSupport }
            try Data(source.utf8).write(to: file, options: .atomic)
        }
        try Data(startup.utf8).write(to: directory.appendingPathComponent("js/browser-startup.js"), options: .atomic)
    }

    private struct IncompatibleExtension: LocalizedError {
        let path: String

        var errorDescription: String? { "The uBlock Origin Lite release changed in \(path)." }
    }

    private static let startup = #"""
    const runtime = self.browser.runtime;
    try {
        const { starting, cachedRulesets } = await runtime.sendNativeMessage('com.itsbrowser', { event: 'prepare' });
        if ( typeof starting !== 'boolean' ) { throw new Error('Content blocking preparation failed'); }
        self.browserStartingBlocker = starting;
        self.browserCachedRulesets = cachedRulesets;
        await import('./background.js');
    } catch ( reason ) {
        runtime.sendNativeMessage('com.itsbrowser', { event: 'error', message: String(reason) }).catch(() => {});
    }

    """#

    private static let patches: [(String, [(String, String)])] = [
        ("js/background.js", [
            (#"""
            async function start() {
                await loadRulesetConfig();
            """#,
             #"""
            async function start() {
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

            """#),
            (#"""
                    enabledRulesets,
                } = await enableRulesets(rulesetConfig.enabledRulesets);
            """#,
             #"""
                    enabledRulesets,
                    error,
                } = await enableRulesets(rulesetConfig.enabledRulesets);
                if ( error ) { throw new Error(error); }
            """#),
            (#"""
                    rulesetConfig.version = currentVersion;
                    await patchDefaultRulesets();
                    saveRulesetConfig();
            """#,
             #"""
                    if ( rulesetConfig.version !== '' ) { await reapplyBrowserRulesets(); }
                    await patchDefaultRulesets();
            """#),
            (#"""
                await processDeferredTasks();

                // Required to ensure
            """#,
             #"""
                await processDeferredTasks();
                if ( isNewVersion ) {
                    rulesetConfig.version = currentVersion;
                    await saveRulesetConfig();
                }

                // Required to ensure
            """#),
            (#"""
                if ( isNewVersion ) {
                    updateDynamicAndSessionRules();
                } else {
                    updateSessionRules();
                }
            """#,
             #"""
                if ( !stockUpdated ) {
                    const result = await (isNewVersion ? updateDynamicAndSessionRules() : updateSessionRules());
                    if ( result?.error ) { throw new Error(result.error); }
                    if ( result === undefined ) { await reapplyBrowserRulesets(); }
                }
            """#),
            (#"const isFullyInitialized = start().then(( ) => {"#,
             #"""
            const isFullyInitialized = start().then(async () => {
                if ( await getDefaultFilteringMode() !== 3 ) {
                    await setDefaultFilteringMode(3);
                    await registerContentScripts();
                }
                const scripts = await getRegisteredContentScripts();
                if ( self.browserCachedRulesets && scripts.includes('css-generic-all') === false ) {
                    throw new Error('Complete filtering scripts could not be registered');
                }
                const snapshot = await browserCacheableRulesets(scripts);
                await runtime.sendNativeMessage('com.itsbrowser', { event: 'ready', snapshot });
            """#),
            (#"""
            }).catch(reason => {
                ubolErr(reason);
            """#,
             #"""
            }).catch(reason => {
                browser.runtime.sendNativeMessage('com.itsbrowser', { event: 'error', message: String(reason) }).catch(() => {});
                ubolErr(reason);
            """#),
        ]),
        ("js/ext.js", [
            (#"if ( extURL.startsWith('safari-web-extension:') ) { return 'safari'; }"#,
             #"if ( extURL.startsWith('safari-web-extension:') || extURL.startsWith('webkit-extension:') ) { return 'safari'; }"#),
        ]),
        ("js/mode-manager.js", [
            (#"""
                optimal: [ 'all-urls' ],
                complete: [],
            """#,
             #"""
                optimal: [],
                complete: [ 'all-urls' ],
            """#),
            (#"    filteringModesToDNR(userModes);"#,
             #"    if ( !self.browserCachedRulesets ) { filteringModesToDNR(userModes); }"#),
        ]),
        ("js/ruleset-manager.js", [
            (#"        if ( ruleset.group === 'imported' ) { continue; }"#,
             #"        if ( ruleset.group === 'imported' || ruleset.id === 'spa-1' ) { continue; }"#),
            (#"export async function getEnabledRulesets() {"#,
             #"""
            export async function getEnabledRulesets() {
                if ( self.browserCachedRulesets ) { return self.browserCachedRulesets; }
            """#),
        ]),
        ("js/ext-compat.js", [
            (#"async function forceEnableRulesets(windowId) {"#,
             #"""
            async function forceEnableRulesets(windowId) {
                if ( self.browserCachedRulesets ) { return; }
            """#),
        ]),
    ]

    private static let backgroundSupport = #"""


    async function reapplyBrowserRulesets() {
        const ids = await dnr.getEnabledRulesets();
        if ( ids.length !== 0 ) {
            await dnr.updateEnabledRulesets({ enableRulesetIds: ids, disableRulesetIds: ids });
        }
    }

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

    """#
}
