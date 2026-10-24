namespace CrestCore.Contracts;

/// Where a pinned or saved tab opens after it is closed: the page it last
/// showed, or its saved URL. The stored preferences spell a policy as its
/// `Name`, so a name never changes. A policy travels as its index in `All`,
/// so `All` is append-only.
public sealed class SavedTabClosePolicy {
    #region Variables

    public static readonly SavedTabClosePolicy ResumeLastLocation = new(name: "resumeLastLocation",
        title: "Resume last location");

    public static readonly SavedTabClosePolicy ReturnToSavedUrl = new(name: "returnToSavedURL", title: "Return to saved URL");

    public static IReadOnlyList<SavedTabClosePolicy> All { get; } = [ResumeLastLocation, ReturnToSavedUrl];

    public string Name { get; }

    /// What the tab settings call the policy.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SavedTabClosePolicy(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SavedTabClosePolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion
}
