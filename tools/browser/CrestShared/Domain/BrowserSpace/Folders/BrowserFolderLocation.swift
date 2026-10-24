/// Placement selects retention and sync policy; both locations use the same tree.
enum BrowserFolderLocation: String, Codable, Equatable, Sendable {
    case saved
    case current

    var tabPlacement: TabPlacement { self == .saved ? .saved : .current }
}
