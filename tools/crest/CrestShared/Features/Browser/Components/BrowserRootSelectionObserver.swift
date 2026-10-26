import SwiftUI

/// The two changes a browser root has to hear about before anything else: what
/// is selected, and whether the Space holding it is locked.
///
/// Both are handed over as `(previous, current)` pairs of whole snapshots
/// rather than as separate flags, because every consumer's question is about
/// the *transition* — a tab change and a Space change want different work, and
/// a lock that has just lifted is a different situation from one that was
/// already up. Splitting the pair apart is the caller's business, so a shell
/// that needs a coarser or finer split does it at its own call site without
/// changing what is observed.
///
/// Generic over the snapshots because the two shells watch different things: a
/// windowed shell's page presentation follows the selected tab, and a shell
/// that also has to decide page *residency* watches the profile and session
/// revision alongside it.
struct BrowserRootSelectionObserver<
    Selection: Equatable,
    Lock: Equatable
>: ViewModifier {
    let selection: Selection
    let lock: Lock

    /// Whether the lock closure also runs on the first evaluation.
    ///
    /// A shell whose chrome has a locked-Space arrangement of its own needs to
    /// be told about a lock that is already up when the root appears, not only
    /// about one that goes up later. A shell that arranges nothing special has
    /// no first-evaluation work to do, and firing there would only re-run a
    /// selection synchronisation that its preparation is about to perform.
    let evaluatesLockInitially: Bool

    let selectionChanged: (Selection, Selection) -> Void
    let lockChanged: (Lock, Lock) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: selection) { previous, current in
                selectionChanged(previous, current)
            }
            .onChange(of: lock, initial: evaluatesLockInitially) {
                previous, current in
                lockChanged(previous, current)
            }
    }
}
