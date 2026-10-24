import SwiftUI

/// How a download's decorative feedback icon moves from where the person
/// clicked to the Downloads destination in the sidebar, carrying its own
/// animation, opacity and scale.
struct BrowserDownloadFeedbackPresentation: Hashable, Sendable {
    // MARK: - Static Variables

    /// The icon flies from the link to the destination.
    static let flight = BrowserDownloadFeedbackPresentation(
        name: "flight", arrival: .spring(duration: 0.68, bounce: 0.16), departsFromSource: true,
        departingOpacity: 1, arrivedOpacity: 0.84, departingScale: 1)

    /// With Reduce Motion, the icon fades in at the destination.
    static let destinationFade = BrowserDownloadFeedbackPresentation(
        name: "destinationFade", arrival: .easeOut(duration: 0.24), departsFromSource: false,
        departingOpacity: 0, arrivedOpacity: 0.9, departingScale: 0.92)

    /// Nothing shows.
    static let hidden = BrowserDownloadFeedbackPresentation(
        name: "hidden", arrival: nil, departsFromSource: false, departingOpacity: 0, arrivedOpacity: 0,
        departingScale: 1)

    // MARK: - Variables

    let name: String

    /// How the icon arrives, or nil when it never moves.
    let arrival: Animation?

    /// Whether the icon starts where the person clicked rather than at the
    /// destination.
    let departsFromSource: Bool

    let departingOpacity: Double
    let arrivedOpacity: Double
    let departingScale: CGFloat

    // MARK: - Initializers

    private init(
        name: String, arrival: Animation?, departsFromSource: Bool, departingOpacity: Double,
        arrivedOpacity: Double, departingScale: CGFloat
    ) {
        self.name = name
        self.arrival = arrival
        self.departsFromSource = departsFromSource
        self.departingOpacity = departingOpacity
        self.arrivedOpacity = arrivedOpacity
        self.departingScale = departingScale
    }

    /// The feedback for a download from a known source toward a sidebar
    /// destination: none unless both are known, and a fade in place of the
    /// flight when the person asks for reduced motion.
    static func resolve(
        hasSource: Bool,
        hasSidebarDestination: Bool,
        reduceMotion: Bool
    ) -> BrowserDownloadFeedbackPresentation {
        guard hasSource, hasSidebarDestination else { return .hidden }
        return reduceMotion ? .destinationFade : .flight
    }

    // MARK: - Actions - Presentation

    func opacity(hasArrived: Bool) -> Double {
        hasArrived ? arrivedOpacity : departingOpacity
    }

    func scale(hasArrived: Bool) -> CGFloat {
        hasArrived ? 1 : departingScale
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserDownloadFeedbackPresentation, rhs: BrowserDownloadFeedbackPresentation) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
