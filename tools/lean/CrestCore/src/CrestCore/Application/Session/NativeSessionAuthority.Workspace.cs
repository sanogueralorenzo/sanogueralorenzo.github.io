using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Imports

    internal SessionEdit Importing(SessionState basis, ImportWorkspace intent, IReadOnlyList<SpaceState> spaces,
        DateTimeOffset now, IIdSource ids, Action<NativeWorkspaceImport> apply) {
        if (!workspaceKind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspaceId));
        var followUp = new WindowFollowUp(IssuingWindow(intent.WindowId));
        var import = new NativeWorkspaceImport(basis, spaces);
        apply(import);
        var result = import.Finish(now, ids, followUp);
        return new(result.Session, SyncStaging.Import, followUp,
            new SessionTabEvents(result.Copied, Favicon: null, Imported: result.Imported));
    }

    internal ImportedWorkspace Preview(ImportWorkspace intent, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(intent);
        lock (Gate) {
            var edit = Edit(intent, Stamp(now), new SystemIdSource())!;
            var events = edit.Events ?? SessionTabEvents.None;
            return new(edit.Next, events.Imported ?? [], [.. events.Copies.Select(copy => copy.Copied(workspaceId))]);
        }
    }

    internal SessionState Exported() {
        lock (Gate) {
            return session;
        }
    }

    #endregion
}
