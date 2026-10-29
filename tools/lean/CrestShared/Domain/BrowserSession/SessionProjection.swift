import Foundation

extension TabState.Seed {
    /// Platform values derived from the stored tab, with no interop round trip.
    var resolved: TabState {
        let mode =
            storedIconMode ?? TabIconMode.all.filter { mode in
                guard let prefix = mode.inferencePrefix else { return false }
                return prefix.isEmpty || symbol.utf16.count > prefix.utf16.count && symbol.hasPrefix(prefix)
            }.max { $0.inferencePrefix!.utf16.count < $1.inferencePrefix!.utf16.count }!
        let saved = placement.isDurable ? savedURL ?? url : nil
        let away = saved.flatMap { saved in url.map { !PageAddress.samePage(saved, $0) } } ?? false
        let currentIcon =
            mode.followsPage && faviconURL.flatMap { icon in url.map { PageAddress.samePage(icon, $0) } } == true
        return TabState(
            id: id, title: title, url: url, nativeContent: nativeContent, savedURL: savedURL, symbol: symbol,
            faviconURL: faviconURL, iconAccent: iconAccent, storedIconMode: storedIconMode, placement: placement,
            folderID: folderID, splitGroupID: splitGroupID, lastActivatedAt: lastActivatedAt,
            positionModifiedAt: positionModifiedAt, customTitle: customTitle, titleModifiedAt: titleModifiedAt,
            iconMode: mode, displayTitle: SessionTabs.customTitle(customTitle) ?? title,
            isAwayFromSavedAddress: away, pageIconIsCurrent: currentIcon,
            surface: nativeContent != nil ? .nativeView : url == nil ? .startPage : .webPage,
            nativeView: NativeView.named(nativeContent?.kind))
    }
}

extension FolderState.Seed {
    var resolved: FolderState {
        FolderState(
            id: id, location: location, title: title, color: color, parentID: parentID, isCollapsed: isCollapsed,
            collapseModifiedAt: collapseModifiedAt, orderAnchorTabID: orderAnchorTabID, source: source,
            liveOptions: liveOptions, gitHubOptions: liveOptions ?? .default,
            displayColor: color ?? FolderState.defaultColor)
    }
}

extension SpaceSettings.Seed {
    var resolved: SpaceSettings {
        SpaceSettings(
            name: name, browsingPreferences: browsingPreferences, isGitHubFolderDismissed: isGitHubFolderDismissed,
            storedColor: storedColor, color: storedColor ?? .blue)
    }
}

extension ArchivedTabState.Seed {
    var resolved: ArchivedTabState { ArchivedTabState(tab: tab.resolved, archivedAt: archivedAt, reason: reason) }
}

extension SpaceState.Seed {
    var resolved: SpaceState {
        SpaceState(
            id: id, profileID: profileID, settings: settings.resolved, folders: folders.map(\.resolved),
            tabs: tabs.map(\.resolved), archivedTabs: archivedTabs.map(\.resolved), history: history,
            sidebar: SessionSidebar(tabs: tabs, folders: folders).outline)
    }
}

extension SessionState.Seed {
    var resolved: SessionState {
        SessionState(
            spaces: spaces.map(\.resolved), disposableSeedMarker: disposableSeedMarker,
            spaceDeletions: spaceDeletions, appPreferences: appPreferences)
    }
}
