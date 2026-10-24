using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The Quick Window and Peek pages kept as tabs or archived. Transient
    /// presentations do not survive a restart, so the receipts live with the
    /// authority, and a late dismissal cannot archive a page already kept.
    private readonly HashSet<Guid> completedTransients = [];

    #endregion

    #region Actions - Transient pages

    /// Refuses a page whose promotion or archive already completed.
    internal void RequirePendingTransient(Guid? pageId) {
        if (pageId is { } value && completedTransients.Contains(value)) throw new Rejected(new TransientAlreadyCompleted(value));
    }

    /// The Quick Window or Peek page of this workspace that `pageId` names,
    /// open or remembered. Throws `Rejected` when the device knows no such
    /// page.
    internal TransientPage Known(Guid pageId, Pages? pages) =>
        pages?.Transient(pageId) is { } page && page.WorkspaceId == workspaceId ? page : throw new Rejected(new UnknownPage(pageId));

    #endregion
}
