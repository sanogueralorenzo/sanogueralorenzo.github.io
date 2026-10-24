import Foundation

/// A generated fixed set that crosses a JSON boundary as its member's `name`:
/// a policy request or answer, including as a dictionary key. Decoding a name
/// this build does not know fails, so a tolerant reader decides what an
/// unknown name means.
protocol CoreNamedValue: Codable, CodingKeyRepresentable {
    var name: String { get }

    static func named(_ name: String?) -> Self?
}

extension CoreNamedValue {
    // MARK: - Variables

    var codingKey: any CodingKey {
        NameKey(name)
    }

    // MARK: - Initializers

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let value = Self.named(name) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown \(Self.self) \(name)")
        }
        self = value
    }

    init?<Key: CodingKey>(codingKey: Key) {
        guard let value = Self.named(codingKey.stringValue) else { return nil }
        self = value
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

/// A member's name as a dictionary key.
private struct NameKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ name: String) {
        stringValue = name
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}

extension AutomaticDownloadAction: CoreNamedValue {}

extension ArchiveReason: CoreNamedValue {}

extension BlockedPopupEvent: CoreNamedValue {}

extension BlockedPopupStatus: CoreNamedValue {}

extension ContentBlockingPolicy: CoreNamedValue {}

extension CurrentTabCleanup: CoreNamedValue {}

extension DataRetention: CoreNamedValue {}

extension DevicePlatform: CoreNamedValue {}

extension ExternalLinkDestination: CoreNamedValue {}

extension ExternalSchemeDisposition: CoreNamedValue {}

extension HostedNotificationRequestAction: CoreNamedValue {}

extension LinkNavigationDecision: CoreNamedValue {}

extension LinkPeekModifier: CoreNamedValue {}

extension LinkRouteMatch: CoreNamedValue {}

extension MemoryPressureLevel: CoreNamedValue {}

extension NumberedSelectionTarget: CoreNamedValue {}

extension QuickWindowArchivePolicy: CoreNamedValue {}

extension SetupEntry: CoreNamedValue {}

extension ShortcutCommand: CoreNamedValue {}

extension ShortcutSpecialKey: CoreNamedValue {}

extension SitePermission: CoreNamedValue {}

extension SitePermissionDecision: CoreNamedValue {}

extension SpaceAccent: CoreNamedValue {}

extension SyncDeletionReason: CoreNamedValue {}

extension TabIconMode: CoreNamedValue {}

extension TabPlacement: CoreNamedValue {}
