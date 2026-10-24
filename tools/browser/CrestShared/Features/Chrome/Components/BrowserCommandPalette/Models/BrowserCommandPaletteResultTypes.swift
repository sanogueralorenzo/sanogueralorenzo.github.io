import Foundation

/// One row the palette shows, at its place in keyboard order.
struct BrowserCommandPaletteItem: Identifiable, Equatable, Sendable {
    // MARK: - Variables

    let index: Int
    let row: PaletteRow

    var id: BrowserCommandPaletteRowID { BrowserCommandPaletteRowID(row) }
}

/// The rows of one section of the palette, in the core's order.
struct BrowserCommandPaletteGroup: Identifiable, Equatable, Sendable {
    // MARK: - Variables

    let section: PaletteSection
    let items: [BrowserCommandPaletteItem]

    var id: PaletteSection { section }

    // MARK: - Actions - Grouping

    /// The groups of `answer`, numbering their rows in the order the palette
    /// steps through them.
    static func groups(of answer: PaletteAnswer) -> [Self] {
        var index = 0
        return answer.groups.map { group in
            BrowserCommandPaletteGroup(
                section: group.section,
                items: group.rows.map { row in
                    defer { index += 1 }
                    return BrowserCommandPaletteItem(index: index, row: row)
                })
        }
    }
}

/// What a palette row stands for, so a row keeps its identity while the
/// results around it change.
struct BrowserCommandPaletteRowID: Hashable, Sendable {
    // MARK: - Variables

    let kind: PaletteRowKind
    let subject: UUID?
    let tab: UUID?
    let address: String?
    let command: ShortcutCommand?
    let title: String

    // MARK: - Initializers

    init(_ row: PaletteRow) {
        kind = row.kind
        subject = row.subjectID
        tab = row.tabID
        address = row.address
        command = row.command
        title = row.title
    }
}
