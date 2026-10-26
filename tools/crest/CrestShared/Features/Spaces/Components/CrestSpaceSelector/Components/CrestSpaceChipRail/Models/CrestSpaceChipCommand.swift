import SwiftUI

/// One context-menu command on a Space chip.
struct CrestSpaceChipCommand: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    static func rename(_ perform: @escaping () -> Void) -> Self {
        CrestSpaceChipCommand(
            id: "rename",
            title: "Rename",
            systemImage: "pencil",
            perform: perform
        )
    }

    static func customize(_ perform: @escaping () -> Void) -> Self {
        CrestSpaceChipCommand(
            id: "customize",
            title: "Customize",
            systemImage: "paintpalette",
            perform: perform
        )
    }

    static func delete(_ perform: @escaping () -> Void) -> Self {
        CrestSpaceChipCommand(
            id: "delete",
            title: "Delete",
            systemImage: "trash",
            isDestructive: true,
            perform: perform
        )
    }
}
