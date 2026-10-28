namespace CrestCore.Contracts;

/// A page without a tab, hosted by Settings or a system authentication window.
public sealed class TransientPresentation {
    #region Static Variables

    public static readonly TransientPresentation Settings = new(name: "settings");
    public static readonly TransientPresentation Authentication = new(name: "authentication");
    public static IReadOnlyList<TransientPresentation> All { get; } = [Settings, Authentication];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private TransientPresentation(string name) { Name = name; }

    #endregion

    #region Actions - Lookup

    public static TransientPresentation? Named(string? name) => All.FirstOrDefault(presentation => presentation.Name == name);

    #endregion
}
