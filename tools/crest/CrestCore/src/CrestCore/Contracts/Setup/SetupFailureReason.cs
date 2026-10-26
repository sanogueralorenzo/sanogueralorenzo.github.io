namespace CrestCore.Contracts;

/// Why setup could not go on with an import, and where it goes back to try
/// again. The platform words a failure with the browser it names; a read or
/// import that was refused carries the words of what refused it. A reason
/// travels as its index in `All`, so `All` is append-only.
public sealed class SetupFailureReason {
    #region Static Variables

    /// The browser is no longer installed.
    public static readonly SetupFailureReason SourceUnavailable = new(name: "sourceUnavailable", returnsToReview: false);
    /// The folder the person chose holds none of the browser's data.
    public static readonly SetupFailureReason DataFolder = new(name: "dataFolder", returnsToReview: false);
    /// Reading the browser's data failed.
    public static readonly SetupFailureReason Read = new(name: "read", returnsToReview: false);
    /// Importing the review, or its passwords, failed.
    public static readonly SetupFailureReason Import = new(name: "import", returnsToReview: true);

    public static IReadOnlyList<SetupFailureReason> All { get; } = [SourceUnavailable, DataFolder, Read, Import];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether setup goes back to the review, rather than to choosing browsers.
    public bool ReturnsToReview { get; }

    #endregion

    #region Constructors

    private SetupFailureReason(string name, bool returnsToReview) {
        Name = name;
        ReturnsToReview = returnsToReview;
    }

    #endregion

    #region Actions - Lookup

    public static SetupFailureReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion
}
