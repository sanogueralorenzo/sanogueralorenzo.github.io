namespace CrestCore.Contracts;

/// The current stage of importing another browser.
public sealed class ImportStep {
    #region Types

    public enum Kinds { ImportBrowser, Review, Complete }

    #endregion

    #region Static Variables

    public static readonly ImportStep ImportBrowser = new(Kinds.ImportBrowser, "importBrowser");
    public static readonly ImportStep Review = new(Kinds.Review, "review");
    public static readonly ImportStep Complete = new(Kinds.Complete, "complete");
    public static IReadOnlyList<ImportStep> All { get; } = [ImportBrowser, Review, Complete];

    #endregion

    #region Variables

    public Kinds Kind { get; }
    public string Name { get; }

    #endregion

    #region Constructors

    private ImportStep(Kinds kind, string name) { Kind = kind; Name = name; }

    #endregion

    #region Actions - Lookup

    public static ImportStep? Named(string? name) => All.FirstOrDefault(step => step.Name == name);

    #endregion
}
