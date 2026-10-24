import CoreGraphics

/// The axis the reader drags the widget deck along. The front card tracks the
/// drag on it, and the cards behind keep their stacked slot offsets.
struct BrowserSidebarWidgetDeckGestureAxis: Equatable, Sendable {
    // MARK: - Static Variables

    static let horizontal = Self(
        name: "horizontal",
        primaryTranslation: { translation in translation.width },
        cardOffset: { trackedTranslation, slotOffset in
            CGSize(width: trackedTranslation, height: slotOffset)
        }
    )

    static let vertical = Self(
        name: "vertical",
        primaryTranslation: { translation in translation.height },
        cardOffset: { trackedTranslation, slotOffset in
            CGSize(width: 0, height: slotOffset + trackedTranslation)
        }
    )

    /// The axis this platform's deck flips along.
    static var current: Self {
        #if os(iOS)
            .vertical
        #else
            .horizontal
        #endif
    }

    // MARK: - Variables

    let name: String

    private let primaryTranslationOf: @Sendable (CGSize) -> CGFloat
    private let cardOffsetFor: @Sendable (CGFloat, CGFloat) -> CGSize

    // MARK: - Initializers

    private init(
        name: String,
        primaryTranslation: @escaping @Sendable (CGSize) -> CGFloat,
        cardOffset: @escaping @Sendable (CGFloat, CGFloat) -> CGSize
    ) {
        self.name = name
        self.primaryTranslationOf = primaryTranslation
        self.cardOffsetFor = cardOffset
    }

    // MARK: - Actions - Gesture

    /// How far a drag of `translation` travelled along the axis.
    func primaryTranslation(of translation: CGSize) -> CGFloat {
        primaryTranslationOf(translation)
    }

    /// Where a card sits, given its slot offset and the drag it tracks.
    func cardOffset(trackedTranslation: CGFloat, slotOffset: CGFloat) -> CGSize {
        cardOffsetFor(trackedTranslation, slotOffset)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
