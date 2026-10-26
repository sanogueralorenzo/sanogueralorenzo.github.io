using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a page surface shows for a tab whose surface is `Surface`, or for no
/// tab: whether its engine holds a page for it, whether that page's navigation
/// or its process failed, and whether the surface restores an unloaded page by
/// itself. It reads no state, so a view may ask it without an app.
public sealed record PresentPage(TabSurface? Surface, bool HasPage, bool HasNavigationFailure, bool HasProcessFailure,
    bool RestoresUnloaded) : StandaloneQuery<PagePresented> {
    #region Actions - Answering

    internal override PagePresented Answer(StandaloneContext context) => new(PagePresentation.Of(this));

    #endregion
}
