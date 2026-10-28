struct BrowserReaderModeSnapshot: Equatable, Sendable {
    let isActive: Bool
    let title: String
    let text: String
    let unsafeElementCount: Int
}
