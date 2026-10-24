import SwiftUI

/// The layer a transient overlay grows out of its source link.
enum BrowserTransientEntranceTarget: Equatable, Sendable {
    /// Only the page grows; the controls stay put and fade in.
    case pageCard

    /// The card and its controls grow together as one assembly.
    case assembly
}

/// How a transient overlay places its card in the room the screen gives it.
///
/// Peek and Quick Window are one surface, but the room around that surface is
/// not the same everywhere. A pointer overlay stands inside a window whose
/// leading chrome the person can still see and reach, so it keeps clear of
/// that chrome and hangs its controls above the card. A handheld overlay owns
/// the whole screen and fills the safe area, with its controls under a thumb.
/// A large touch screen has the room to float a card at a fraction of its size
/// with the controls beneath it.
///
/// The arrangement names those three rooms so one surface can lay itself out
/// instead of asking which target compiled it. It is an explicit shell input
/// rather than a capability bit: what varies is how much room there is and how
/// the card is reached, not whether a shell can do something.
struct BrowserTransientCardArrangement: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    /// The share of its container a pointer card fills, and that a Quick Window
    /// takes of the page or screen it opens over.
    static let windowContentFraction: CGFloat = 0.8

    /// A card beside a window's reserved leading chrome, sized at the shared
    /// window fraction and dismissed with the pointer or a key.
    static let pointer = BrowserTransientCardArrangement(
        name: "pointer", entranceTarget: .pageCard, placesControlsAboveCard: true, controlAlignment: .trailing,
        controlSpacing: 10, constrainsControlBarToMaximumWidth: false, controlBarPadding: 0,
        framesContent: { containerSize, reservedLeadingWidth, layoutDirection in
            let leadingWidth = min(
                max(reservedLeadingWidth, 0),
                containerSize.width
            )
            return CGRect(
                x: layoutDirection == .leftToRight ? leadingWidth : 0,
                y: 0,
                width: containerSize.width - leadingWidth,
                height: containerSize.height
            )
        },
        sizesCard: { windowContentSize(in: $0) },
        insetsContent: { _ in EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30) },
        cardCornerRadius: 15, cardBorderOpacity: 0.16, cardShadowOpacity: 0.34, cardShadowRadius: 28,
        cardShadowOffsetY: 14)

    /// A card filling a handheld screen's safe area, closed with the control
    /// bar beneath it or by tapping the ground its insets leave showing. The
    /// card itself is all web page, so every gesture over it stays WebKit's.
    static let sheet = BrowserTransientCardArrangement(
        name: "sheet", entranceTarget: .assembly, placesControlsAboveCard: false, controlAlignment: .center,
        controlSpacing: 8, constrainsControlBarToMaximumWidth: true, controlBarPadding: 10,
        framesContent: nil,
        sizesCard: { _ in nil },
        insetsContent: { safeAreaInsets in
            BrowserTransientCardLayout.cardInsets(
                safeAreaInsets: safeAreaInsets,
                minimumHorizontal: 14,
                minimumVertical: 10
            )
        },
        // A thumb-sized card is held closer and rounded more heavily than one
        // read at pointer distance.
        cardCornerRadius: 24, cardBorderOpacity: 0.18, cardShadowOpacity: 0.32, cardShadowRadius: 24,
        cardShadowOffsetY: 12)

    /// A card floating at a fraction of a large touch screen, with room left
    /// around it for the scrim to be a deliberate target.
    static let canvas = BrowserTransientCardArrangement(
        name: "canvas", entranceTarget: .assembly, placesControlsAboveCard: false, controlAlignment: .trailing,
        controlSpacing: 10, constrainsControlBarToMaximumWidth: true, controlBarPadding: 0,
        framesContent: nil,
        sizesCard: { contentSize in
            CGSize(
                width: min(max(contentSize.width * 0.76, 600), 1_180),
                height: min(max(contentSize.height * 0.78, 430), 820)
            )
        },
        insetsContent: { safeAreaInsets in
            BrowserTransientCardLayout.cardInsets(
                safeAreaInsets: safeAreaInsets,
                minimumHorizontal: 28,
                minimumVertical: 28
            )
        },
        cardCornerRadius: 15, cardBorderOpacity: 0.18, cardShadowOpacity: 0.32, cardShadowRadius: 24,
        cardShadowOffsetY: 12)

    /// Every arrangement.
    static let all: [BrowserTransientCardArrangement] = [pointer, sheet, canvas]

    // MARK: - Variables

    let name: String

    let entranceTarget: BrowserTransientEntranceTarget

    /// Whether the controls sit above the card, as they do for a pointer.
    /// Touch arrangements put them within reach of a thumb instead.
    let placesControlsAboveCard: Bool

    let controlAlignment: HorizontalAlignment
    let controlSpacing: CGFloat

    /// Whether the control bar may shrink below its natural width. A touch
    /// screen, or the page column beside a tablet's sidebar, can be narrower
    /// than the bar, so there the bar is a maximum; a pointer window never is,
    /// so there it is a fixed width.
    let constrainsControlBarToMaximumWidth: Bool

    let controlBarPadding: CGFloat

    /// How the arrangement measures the region, card size and insets below.
    private let framesContent: (@Sendable (CGSize, CGFloat, LayoutDirection) -> CGRect)?
    private let sizesCard: @Sendable (CGSize) -> CGSize?
    private let insetsContent: @Sendable (EdgeInsets) -> EdgeInsets

    let cardCornerRadius: CGFloat
    let cardBorderOpacity: Double
    let cardShadowOpacity: Double
    let cardShadowRadius: CGFloat
    let cardShadowOffsetY: CGFloat

    /// Whether tapping the ground the card stands on closes it.
    ///
    /// Every room answers a tap outside the card. A pointer window and a large
    /// touch screen leave generous ground around it. A handheld leaves only the
    /// strip its safe-area insets hold back, which is narrow but reliable, and
    /// on that screen it is the way out beside the close button: a handheld
    /// card's control bar sits at the bottom edge, where a downward drag is the
    /// system's own Reachability gesture rather than the card's.
    var allowsScrimDismissal: Bool { true }

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, entranceTarget: BrowserTransientEntranceTarget, placesControlsAboveCard: Bool,
        controlAlignment: HorizontalAlignment, controlSpacing: CGFloat, constrainsControlBarToMaximumWidth: Bool,
        controlBarPadding: CGFloat,
        framesContent: (@Sendable (CGSize, CGFloat, LayoutDirection) -> CGRect)?,
        sizesCard: @escaping @Sendable (CGSize) -> CGSize?,
        insetsContent: @escaping @Sendable (EdgeInsets) -> EdgeInsets,
        cardCornerRadius: CGFloat, cardBorderOpacity: Double, cardShadowOpacity: Double, cardShadowRadius: CGFloat,
        cardShadowOffsetY: CGFloat
    ) {
        self.name = name
        self.entranceTarget = entranceTarget
        self.placesControlsAboveCard = placesControlsAboveCard
        self.controlAlignment = controlAlignment
        self.controlSpacing = controlSpacing
        self.constrainsControlBarToMaximumWidth = constrainsControlBarToMaximumWidth
        self.controlBarPadding = controlBarPadding
        self.framesContent = framesContent
        self.sizesCard = sizesCard
        self.insetsContent = insetsContent
        self.cardCornerRadius = cardCornerRadius
        self.cardBorderOpacity = cardBorderOpacity
        self.cardShadowOpacity = cardShadowOpacity
        self.cardShadowRadius = cardShadowRadius
        self.cardShadowOffsetY = cardShadowOffsetY
    }

    // MARK: - Actions - Geometry

    /// The region of the container the card is laid out inside, or `nil` where
    /// the card simply fills what it is given.
    func contentFrame(
        in containerSize: CGSize,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection
    ) -> CGRect? {
        framesContent?(containerSize, reservedLeadingWidth, layoutDirection)
    }

    /// The card's own size inside that region, or `nil` where the card takes
    /// everything the stack leaves it.
    func cardSize(in contentSize: CGSize) -> CGSize? {
        sizesCard(contentSize)
    }

    func contentInsets(safeAreaInsets: EdgeInsets) -> EdgeInsets {
        insetsContent(safeAreaInsets)
    }

    /// The size a pointer card or Quick Window takes of `containerSize`.
    static func windowContentSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: containerSize.width * windowContentFraction,
            height: containerSize.height * windowContentFraction
        )
    }

    /// A frame of the window content size, centred in `containerFrame`.
    static func centeredWindowContentFrame(in containerFrame: CGRect) -> CGRect {
        let size = windowContentSize(in: containerFrame.size)
        return CGRect(
            x: containerFrame.midX - (size.width / 2),
            y: containerFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserTransientCardArrangement, rhs: BrowserTransientCardArrangement) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
