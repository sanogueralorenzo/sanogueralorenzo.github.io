import SwiftUI

// The three places where an engine contributes its own site-scoped content to
// a shared surface: the Site Settings permission list, the Site Controls
// popover, and the top of a Space's sidebar. The presentation layer composes
// these names and never mentions an engine's types; each engine's module
// supplies its own implementation of them. The declarations below are the
// WebKit composition — the Chromium framework has its own file, and neither is
// compiled into the other's target: the Chromium framework excludes this file
// in project.yml.

/// Crest's own per-site permission list. WebKit has no permission UI of its
/// own, so the decisions come from Crest's permission centre; each open page's
/// `BrowserPageSitePermissionSession` carries a change to the page at once.
struct BrowserEngineSitePermissionsSection: View {
    let page: BrowserPage
    let origin: SiteOrigin
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isExpanded: Bool

    var body: some View {
        BrowserSitePermissionDisclosure(
            origin: origin,
            spaceID: page.spaceID,
            permissionCenter: permissionCenter,
            isExpanded: $isExpanded
        )
    }
}

/// WebKit's port ships no extensions, so Site Controls has nothing to add.
struct BrowserEngineSiteControlsSection: View {
    let page: BrowserPage
    let space: SpaceModel
    let url: URL?
    let dismiss: () -> Void

    var body: some View { EmptyView() }
}

/// No pinned extension actions without extensions.
struct BrowserEngineSidebarAccessory: View {
    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool

    var body: some View { EmptyView() }
}
