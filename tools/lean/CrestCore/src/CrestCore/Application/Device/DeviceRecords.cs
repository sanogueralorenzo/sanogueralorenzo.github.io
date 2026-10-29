using CrestCore.Contracts;

namespace CrestCore.Application;

/// What the device store holds: every saved window's record, the saved
/// windows the next launch reopens, back to front, the records it adopted
/// from an installed release, the
/// agent preferences.
internal sealed record DeviceRecords(IReadOnlyList<SavedWindow> Windows, IReadOnlyList<Guid> Reopening,
    IReadOnlySet<DeviceAdoption> Adopted) {
    #region Static Variables

    public static readonly DeviceRecords Empty = new([], [],
        new HashSet<DeviceAdoption>());

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
        && Adopted.SetEquals(other.Adopted)
        && Agents.Equals(other.Agents);

    public override int GetHashCode() => HashCode.Combine(Windows.Count, Adopted.Count);

    #endregion
}
