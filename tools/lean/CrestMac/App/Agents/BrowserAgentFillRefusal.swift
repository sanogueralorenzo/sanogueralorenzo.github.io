import Foundation

/// Why the page would not ready an element for an agent to fill, as the
/// fill script names it, and what the agent hears.
struct BrowserAgentFillRefusal: Sendable {
    // MARK: - Static Variables

    /// The page has no element by the uid the agent gave.
    static let unknownElement = Self(name: "unknown") { uid, _ in .unknownElement(uid) }
    /// The element is a menu with no option the value names.
    static let noOption = Self(name: "option") { _, value in
        .refused("The menu has no option labelled or valued \(value).")
    }
    /// The element takes no text.
    static let notEditable = Self(name: "editable") { _, _ in .notEditable }

    static let all: [BrowserAgentFillRefusal] = [unknownElement, noOption, notEditable]

    // MARK: - Variables

    let name: String
    private let explanation: @Sendable (_ uid: String, _ value: String) -> BrowserAgentFailure

    // MARK: - Initializers

    private init(name: String, explanation: @escaping @Sendable (_ uid: String, _ value: String) -> BrowserAgentFailure)
    {
        self.name = name
        self.explanation = explanation
    }

    // MARK: - Actions - Failures

    /// The refusal the fill script named `name`, or nil when it named none
    /// Crest knows.
    static func named(_ name: String?) -> Self? {
        all.first { $0.name == name }
    }

    /// The failure the agent hears for filling element `uid` with `value`.
    func failure(uid: String, value: String) -> BrowserAgentFailure {
        explanation(uid, value)
    }
}
