import SwiftUI
import UIKit

extension MobileBrowserCommandContext {
    /// The on-screen direction resolved against this shell's layout, so the
    /// hardware-keyboard menu and the launcher ask the same question.
    func canMoveFocusedSplitCard(
        _ direction: BrowserSplitCardMoveDirection
    ) -> Bool {
        canMoveFocusedSplitCard(
            direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    func moveFocusedSplitCard(_ direction: BrowserSplitCardMoveDirection) {
        moveFocusedSplitCard(
            direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    /// iPadOS does not let a reader rebind these yet, so the launcher shows the
    /// command names without chords.
    @MainActor
    var paletteRegistry: BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: MobileBrowserCommand.all.filter { isOffered($0.command) && $0.isAvailable(self) }.map(\.command),
            perform: performFromPalette,
            switchSpace: selectSpace,
            reopenArchivedTab: reopenArchivedTab,
            copy: { UIPasteboard.general.string = $0 }
        )
    }

    /// Toggles content blocking for the page the window shows, which finishes
    /// on its own once the engine applies it.
    @MainActor
    func beginTogglingContentBlocking() {
        Task { await toggleContentBlocking() }
    }

    /// Runs `command` as the platform does, when it has an answer for it and
    /// can run it now.
    @MainActor
    private func performFromPalette(_ command: ShortcutCommand) {
        guard let action = MobileBrowserCommand.of(command), action.isAvailable(self) else { return }
        action.run(self)
    }
}
