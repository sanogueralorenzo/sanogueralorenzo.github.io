using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// An engine tab group an extension made in a Space of the persistent
/// session, which the folder of the same identity shows, as the device store
/// keeps it so the folder follows the group after the next launch: the
/// engine whose pages it groups, and the group's own title and color, which
/// may differ from its folder's.
internal sealed record TabGroupRecord(Guid Id, Guid SpaceId, string Title, TabGroupColor Color);

#endregion

/// What the device store holds: every saved window's record, the saved
/// windows the next launch reopens, back to front, the persistent session's
/// site permission choices in storage order, the
/// records it has adopted from an installed release, the
/// tab groups whose folders follow them, and the agent preferences.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<Guid> Reopening,
    IReadOnlyList<SitePermissionRecord> SitePermissions,
    IReadOnlySet<DeviceAdoption> Adopted,
    IReadOnlyList<TabGroupRecord> TabGroups) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [], [],
        new HashSet<DeviceAdoption>(), TabGroups: []);

    #endregion

    #region Variables

    /// Whether agents may use Crest, and what the person allowed them.
    public AgentPreferences Agents { get; init; } = AgentPreferences.Off;

    #endregion

    #region Actions - Adoption

    /// These records, having adopted `adoption` too.
    public DeviceRecords Adopting(DeviceAdoption adoption) => this with { Adopted = new HashSet<DeviceAdoption>(Adopted) { adoption } };

    #endregion

    #region Actions - Equality

    public bool Equals(DeviceRecords? other) => other is not null
        && Windows.SequenceEqual(other.Windows)
        && Reopening.SequenceEqual(other.Reopening)
        && SitePermissions.SequenceEqual(other.SitePermissions)
        && Adopted.SetEquals(other.Adopted)
        && TabGroups.SequenceEqual(other.TabGroups)
        && Agents.Equals(other.Agents);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, SitePermissions.Count, Adopted.Count);

    #endregion
}
