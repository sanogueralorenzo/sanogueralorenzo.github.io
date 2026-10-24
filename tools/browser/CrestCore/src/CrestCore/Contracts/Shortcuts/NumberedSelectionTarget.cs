namespace CrestCore.Contracts;

/// The ordered collection a numbered shortcut selects from: the stops of the
/// shown Space's sidebar, or the Spaces a window may show.
public sealed class NumberedSelectionTarget {
    #region Types

    /// Each platform selects a tab or a Space with its own code, so the one
    /// place that selects switches over the kind.
    public enum Kinds { Tab, Space }

    #endregion

    #region Static Variables

    public static readonly NumberedSelectionTarget Tab = new(Kinds.Tab, name: "tab",
        choosing: (choices, index) => index < choices.Tabs.Count ? (choices.ShownSpaceId, choices.Tabs[index]) : null);
    public static readonly NumberedSelectionTarget Space = new(Kinds.Space, name: "space",
        choosing: (choices, index) => index < choices.Spaces.Count ? (choices.Spaces[index], null) : null);

    public static IReadOnlyList<NumberedSelectionTarget> All { get; } = [Tab, Space];

    #endregion

    #region Variables

    public Kinds Kind { get; }
    public string Name { get; }

    /// The Space, and the tab in it for a tab, at a zero-based position among
    /// what a window chooses from, or null when there is nothing there.
    private readonly Func<NumberedChoices, int, (Guid SpaceId, Guid? TabId)?> choosing;

    #endregion

    #region Constructors

    private NumberedSelectionTarget(Kinds kind, string name, Func<NumberedChoices, int, (Guid SpaceId, Guid? TabId)?> choosing) {
        Kind = kind;
        Name = name;
        this.choosing = choosing;
    }

    #endregion

    #region Actions - Lookup

    public static NumberedSelectionTarget? Named(string? name) => All.FirstOrDefault(target => target.Name == name);

    /// The Space, and the tab in it for a tab, at the zero-based `index` among
    /// `choices`, or null when there is nothing there.
    public (Guid SpaceId, Guid? TabId)? Choose(NumberedChoices choices, int index) {
        ArgumentNullException.ThrowIfNull(choices);
        return choosing(choices, index);
    }

    #endregion
}
