import CoreGraphics

/// How much room a shell gives the start page, and what it draws behind it.
///
/// The desktop and the expanded touch layout both draw the same wide page; the
/// phone draws a narrower one that scrolls over the Space's banner. Everything
/// that differs between them is measured here, so the surface itself stays one
/// view rather than one view per shell.
struct BrowserStartPageLayout: Equatable {
    let spacing: CGFloat
    let padding: CGFloat
    let maximumWidth: CGFloat
    let markSize: CGFloat
    let privateNoticeSpacing: CGFloat
    /// Whether the stack scrolls, for a shell whose keyboard can cover it.
    let scrollsContent: Bool
    /// Whether the Space's banner shows behind the stack instead of nothing.
    let showsSpaceBanner: Bool
    /// Whether the backdrop reaches under the system safe areas.
    ///
    /// Touch extends it so the banner meets the screen's edges; the desktop
    /// leaves its clear backdrop inside the window's safe area, which is what
    /// keeps the stack centred on the page area rather than on the window.
    let backgroundIgnoresSafeArea: Bool

    static let macOSPage = BrowserStartPageLayout(
        spacing: 28,
        padding: 40,
        maximumWidth: 820,
        markSize: 48,
        privateNoticeSpacing: 6,
        scrollsContent: false,
        showsSpaceBanner: false,
        backgroundIgnoresSafeArea: false
    )

    static let mobileRegularPage = BrowserStartPageLayout(
        spacing: 28,
        padding: 40,
        maximumWidth: 820,
        markSize: 48,
        privateNoticeSpacing: 6,
        scrollsContent: false,
        showsSpaceBanner: false,
        backgroundIgnoresSafeArea: true
    )

    static let mobileCompactPage = BrowserStartPageLayout(
        spacing: 22,
        padding: 24,
        maximumWidth: 620,
        markSize: 48,
        privateNoticeSpacing: 6,
        scrollsContent: true,
        showsSpaceBanner: true,
        backgroundIgnoresSafeArea: true
    )
}
