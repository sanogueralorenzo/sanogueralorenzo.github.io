import CoreGraphics

/// What a Crest button is for. Call sites choose intent instead of restating
/// visual treatment.
enum CrestButtonRole: Equatable, Sendable {
    /// The single action that carries a flow forward.
    case primary
    /// A real alternative to the primary action.
    case secondary
    /// A quiet action belonging to a row of content.
    case tertiary
    /// An action that removes something.
    case destructive
    /// A glyph-only circular control. Callers supply an accessibility label.
    case icon(diameter: CGFloat, isProminent: Bool)
}
