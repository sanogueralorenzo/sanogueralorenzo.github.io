using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A tab's split membership: its split group, if any, its section and its
/// folder.
public readonly record struct SplitMember(Guid? Group, TabPlacement Placement, Guid? Folder) {
    #region Actions - Organization

    /// Each tab's repaired split group. Repair never reorders tabs or rewrites
    /// position clocks. A singleton keeps its membership because the rest of a
    /// sync batch may not have arrived yet.
    public static IReadOnlyList<Guid?> Repair(IReadOnlyList<SplitMember> tabs) {
        var result = new Guid?[tabs.Count];
        HashSet<Guid> retired = [];
        Guid? run = null; TabPlacement? placement = null; Guid? folder = null; int length = 0;
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            if (tab.Group is not { } group || !tab.Placement.HoldsSplits) {
                if (run is { } old) retired.Add(old);
                run = null; length = 0; continue;
            }
            if (run != group) {
                if (run is { } old) retired.Add(old);
                run = null; length = 0;
                if (retired.Contains(group)) continue;
                run = group; placement = tab.Placement; folder = tab.Folder; length = 1;
            } else {
                if (tab.Placement != placement || tab.Folder != folder) { retired.Add(group); run = null; length = 0; continue; }
                if (length >= BrowserTabCollection.MaximumSplitMembers) continue;
                length++;
            }
            result[index] = group;
        }
        return result;
    }

    /// An imported Space must already hold well-formed split runs. Repair
    /// would quietly rewrite a malformed archive; the import is refused
    /// instead, with `InvalidImport`.
    public static void RequireWellFormed(IReadOnlyList<SplitMember> tabs) {
        ArgumentNullException.ThrowIfNull(tabs);
        var repaired = Repair(tabs);
        for (int index = 0; index < tabs.Count; index++)
            if (repaired[index] != tabs[index].Group) throw new Rejected(new InvalidImport(ImportFlaw.MalformedSplit));
    }

    #endregion
}
