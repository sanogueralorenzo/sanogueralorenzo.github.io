using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record LinkNavigation(Guid PageId, string? Url, LinkGesture Gesture) : Query<LinkNavigationAnswer> {
    #region Actions - Answering

    /// Both native link actions and engine activations use the same gesture rules.
    internal override LinkNavigationAnswer Answer(CrestApp app) {
        var page = app.Pages.Hosted(PageId);
        var tab = page is { TabId: { } tabId }
            ? app.Device.Attached(page.WorkspaceId)?.Current.Spaces.FirstOrDefault(space => space.Id == page.SpaceId)?.Tabs
                .FirstOrDefault(candidate => candidate.Id == tabId)
            : null;
        bool preview = Gesture.Modifiers.HasFlag(ShortcutModifiers.Option);
        bool newTab = Gesture.Modifiers.HasFlag(ShortcutModifiers.Command) || Gesture.MiddleClick;
        return new(LinkNavigationDecision.For(Url, Gesture.UserActivated, Gesture.TopLevel, preview, newTab,
            Gesture.Modifiers.HasFlag(ShortcutModifiers.Shift), hasContext: tab is not null, tab?.Placement,
            tab?.SavedAddress));
    }

    #endregion
}
