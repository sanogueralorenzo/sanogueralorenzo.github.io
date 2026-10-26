using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What closing a tab does. A saved or pinned tab keeps its record and only
/// puts its page away; an open tab is archived; the Start Page that is its
/// Space's only tab leaves nothing but its window to close.
public sealed class TabDismissalAction {
    #region Static Variables

    public static readonly TabDismissalAction UnloadPage = new(keepsTab: true, closesWindow: false,
        applies: (placement, _, _) => placement.IsDurable);
    public static readonly TabDismissalAction CloseWindow = new(keepsTab: true, closesWindow: true,
        applies: (_, isStartPage, tabCount) => isStartPage && tabCount < 2);
    public static readonly TabDismissalAction CloseTab = new(keepsTab: false, closesWindow: false, applies: (_, _, _) => true);

    /// The actions in the order they are considered: the first that applies decides.
    public static IReadOnlyList<TabDismissalAction> All { get; } = [UnloadPage, CloseWindow, CloseTab];

    #endregion

    #region Variables

    /// The tab stays in its Space.
    public bool KeepsTab { get; }

    /// Only the tab's window is left to close.
    public bool ClosesWindow { get; }

    /// Whether the action applies to a tab in a section, showing the Start
    /// Page or not, in a Space of so many tabs.
    private readonly Func<TabPlacement, bool, int, bool> applies;

    #endregion

    #region Constructors

    private TabDismissalAction(bool keepsTab, bool closesWindow, Func<TabPlacement, bool, int, bool> applies) {
        KeepsTab = keepsTab;
        ClosesWindow = closesWindow;
        this.applies = applies;
    }

    #endregion

    #region Actions - Lookup

    /// What closing a tab in `placement`'s section does, when it shows the
    /// Start Page or not and its Space holds `tabCount` tabs.
    public static TabDismissalAction Of(TabPlacement placement, bool isStartPage, int tabCount) {
        ArgumentNullException.ThrowIfNull(placement);
        return All.First(action => action.applies(placement, isStartPage, tabCount));
    }

    #endregion
}
