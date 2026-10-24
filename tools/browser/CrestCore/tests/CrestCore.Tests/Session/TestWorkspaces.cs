using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests;

/// Opens the workspaces a test works in the way a platform does, with
/// `OpenWorkspace` from a seed and `BorrowSpace`.
internal static class TestWorkspaces {
    #region Actions - Opening

    /// `session`, a document in the stored format, as the seed of an
    /// `OpenWorkspace`, as a platform builds one.
    public static SessionState Seed(JsonNode session) => StoredSessionCodec.DecodeSession(session);

    /// Opens a workspace of `kind`, persistent unless named, from `session`
    /// and answers the identity the core gave it.
    public static Guid Open(CrestApp app, JsonNode session, WorkspaceKind? kind = null) =>
        Opened(app.Send(new OpenWorkspace(kind ?? WorkspaceKind.Persistent, Seed(session))));

    /// Opens a workspace that borrows the Space `space`, a stored-format Space,
    /// of `owner` and answers its identity.
    public static Guid Borrow(CrestApp app, Guid owner, JsonNode space) =>
        Opened(app.Send(new BorrowSpace(owner, Guid.Parse(space["id"]!["rawValue"]!.GetValue<string>()),
            Guid.Parse(space["profile"]!["id"]!.GetValue<string>()))));

    /// Opens the session `app` keeps in its file, as a launch does, and
    /// answers its workspace with the changes the intent answered.
    public static (Guid Workspace, IReadOnlyList<Change> Answer) OpenStored(CrestApp app) {
        var answer = app.Send(new OpenWorkspace(WorkspaceKind.Persistent, Seed: null));
        return (Opened(answer), answer);
    }

    /// The workspace the intent that answered `changes` opened.
    public static Guid Opened(IReadOnlyList<Change> changes) => changes.OfType<WorkspaceOpened>().Last().WorkspaceId;

    /// A memory-only session of `kind`, persistent unless named, over
    /// `session`, as `OpenWorkspace` makes one from a seed, for a test of the
    /// session on its own.
    public static NativeSessionAuthority Session(JsonNode session, WorkspaceKind? kind = null) =>
        new(kind ?? WorkspaceKind.Persistent, StoredSessionCodec.DecodeSession(session));

    #endregion
}
