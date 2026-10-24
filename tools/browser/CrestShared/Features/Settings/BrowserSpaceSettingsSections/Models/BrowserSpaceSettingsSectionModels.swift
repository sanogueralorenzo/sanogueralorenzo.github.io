import Foundation
import SwiftUI

/// One Space's download destination, as the shell that owns the file system
/// hands it over.
///
/// Choosing a folder is a system panel and remembering one is a security-scoped
/// bookmark, so the state and both system touches stay in the shell that has
/// them. This carries only what the section draws and the two things it can ask
/// for.
struct BrowserSpaceDownloadSettings {
    /// Whether every download stops to ask where it should go.
    var asksWhereToSave: Binding<Bool>

    /// The display name of the folder downloads land in.
    var directoryName: String

    /// Whether ``directoryName`` is a folder the reader chose rather than the
    /// system default. The reset action has nothing to undo otherwise.
    var usesCustomDirectory: Bool

    /// Why the last folder change failed, if it did.
    var errorMessage: String?

    /// Opens the shell's folder chooser.
    var chooseDirectory: () -> Void

    /// Returns this Space to the system download folder.
    var resetDirectory: () -> Void
}
