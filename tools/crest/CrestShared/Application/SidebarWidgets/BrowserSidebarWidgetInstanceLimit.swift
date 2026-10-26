import Foundation

/// How many cards one widget kind shows at once, and which of the instances
/// its source publishes they are.
struct BrowserSidebarWidgetInstanceLimit: Equatable, Sendable {
    // MARK: - Static Variables

    /// The kind shows one card: the instance with the lowest identifier.
    static let single = Self(name: "single", isSingle: true) { instances in
        instances.sorted { $0.id.id < $1.id.id }.prefix(1).map { $0 }
    }

    /// The kind shows a card for every distinct instance, the last one
    /// published under an identifier standing for it.
    static let multiple = Self(name: "multiple", isSingle: false) { instances in
        var unique: [BrowserSidebarWidgetID: BrowserSidebarWidgetInstance] = [:]
        for instance in instances { unique[instance.id] = instance }
        return unique.values.sorted { $0.id.id < $1.id.id }
    }

    // MARK: - Variables

    let name: String

    /// Whether the kind shows only its first card wherever cards are shown.
    let isSingle: Bool

    private let normalization: @Sendable ([BrowserSidebarWidgetInstance]) -> [BrowserSidebarWidgetInstance]

    // MARK: - Initializers

    private init(
        name: String, isSingle: Bool,
        normalization: @escaping @Sendable ([BrowserSidebarWidgetInstance]) -> [BrowserSidebarWidgetInstance]
    ) {
        self.name = name
        self.isSingle = isSingle
        self.normalization = normalization
    }

    // MARK: - Actions - Instances

    /// The cards the kind shows from `instances`, its source's latest
    /// publication, in identifier order.
    func normalize(_ instances: [BrowserSidebarWidgetInstance]) -> [BrowserSidebarWidgetInstance] {
        normalization(instances)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
