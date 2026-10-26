namespace CrestCore.Contracts;

/// Why the cloud's zone of Crest's records stopped existing.
///
/// A choice travels as its index in `All`, so `All` is append-only.
public sealed class CloudZoneLoss {
    #region Variables

    /// Somebody deleted Crest's data from iCloud: a decision Crest does not
    /// overrule by uploading everything again.
    public static readonly CloudZoneLoss Deleted = new(name: "deleted", restoresLocalRecords: false);
    /// iCloud purged the zone, which is also a decision.
    public static readonly CloudZoneLoss Purged = new(name: "purged", restoresLocalRecords: false);
    /// iCloud discarded the encrypted contents while the person kept their
    /// data, so this device's records are the surviving copy.
    public static readonly CloudZoneLoss EncryptedDataReset = new(name: "encryptedDataReset", restoresLocalRecords: true);

    public static IReadOnlyList<CloudZoneLoss> All { get; } = [Deleted, Purged, EncryptedDataReset];

    public string Name { get; }

    /// Whether the zone is rebuilt from this device's records.
    public bool RestoresLocalRecords { get; }

    #endregion

    #region Constructors

    private CloudZoneLoss(string name, bool restoresLocalRecords) {
        Name = name;
        RestoresLocalRecords = restoresLocalRecords;
    }

    #endregion
}
