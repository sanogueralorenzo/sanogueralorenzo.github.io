import Foundation

/// A window's sidebar layout on this device: how wide the sidebar is and
/// whether it is shown. Only the platform reads it. What the window shows,
/// and its split columns, are the core's window state.
struct BrowserWindowState: Equatable, Identifiable, Sendable {
    let id: UUID
    private(set) var sidebarWidth: Double?
    private(set) var sidebarIsPresented: Bool?

    init(id: UUID, sidebarWidth: Double? = nil, sidebarIsPresented: Bool? = nil) {
        self.id = id
        self.sidebarWidth = sidebarWidth
        self.sidebarIsPresented = sidebarIsPresented
    }

    mutating func captureSidebar(width: Double? = nil, isPresented: Bool? = nil) {
        if let width, width.isFinite, width > 0 {
            sidebarWidth = width
        }
        if let isPresented {
            sidebarIsPresented = isPresented
        }
    }
}

// MARK: - Codable

/// `BrowserWindowLayouts` keeps these in the defaults, so a window's identity
/// keeps the stored spelling a build before S6.2 reads.
extension BrowserWindowState: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case sidebarWidth
        case sidebarIsPresented
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIdentity(forKey: .id),
            sidebarWidth: try container.decodeIfPresent(Double.self, forKey: .sidebarWidth),
            sidebarIsPresented: try container.decodeIfPresent(Bool.self, forKey: .sidebarIsPresented))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(id, forKey: .id)
        try container.encodeIfPresent(sidebarWidth, forKey: .sidebarWidth)
        try container.encodeIfPresent(sidebarIsPresented, forKey: .sidebarIsPresented)
    }
}
