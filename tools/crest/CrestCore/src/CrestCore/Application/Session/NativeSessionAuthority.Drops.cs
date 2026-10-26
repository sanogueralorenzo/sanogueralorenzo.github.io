using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// A lift resolved in the Space the window shows: the selection's work, and
    /// the tab it moves alone when it is one tab.
    internal sealed record Lift(SelectionEdit Work, BrowserTab? Alone) {
        #region Variables

        /// Whether the lift holds only pinned tabs.
        public bool PinsOnly => !Work.Selected.HoldsFolders && Work.Selected.Members.All(tab => tab.Placement == TabPlacement.Pinned);

        #endregion
    }

    #endregion

    #region Actions - Drops

    /// Throws the rule that refuses the lift itself, whatever it drops on: the
    /// window no longer shows the Space or the selection changed, the Space
    /// takes no edits, or pinned tabs lift with others.
    internal void CheckLift(Guid windowId, Guid spaceId, TabSelection selection) {
        ArgumentNullException.ThrowIfNull(selection);
        lock (Gate) _ = Lifting(IntentBasis(), windowId, spaceId, selection);
    }

    /// The lift of `selection` from `windowId`'s sidebar, resolved in the Space
    /// it shows, which pinned tabs never leave with others.
    internal Lift Lifting(SessionState basis, Guid windowId, Guid spaceId, TabSelection selection) {
        var work = Selecting(basis, windowId, spaceId, selection);
        var alone = work.Selected.Roots is [{ IsFolder: false } root] ? work.Edited.Tab(root.Id) : null;
        var members = work.Selected.Members;
        if (alone is null && members.Any(tab => tab.Placement == TabPlacement.Pinned)
            && (work.Selected.HoldsFolders || members.Any(tab => tab.Placement != TabPlacement.Pinned)))
            throw new Rejected(new PinnedTabsDragAlone());
        return new(work, alone);
    }

    #endregion
}
