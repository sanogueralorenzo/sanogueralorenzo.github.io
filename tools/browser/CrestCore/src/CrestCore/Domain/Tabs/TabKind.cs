using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

public enum TabRenderType { WebRender, UiNative }

#endregion

/// <summary>The content a tab presents. Persisted native kind names are resolved at the boundary.</summary>
public sealed record TabKind {
    #region Variables

    public string Name { get; }
    public TabRenderType RenderType { get; }
    public string? NativeKind { get; }
    public string Symbol { get; }
    public bool IsStartPage { get; }
    public bool IsWebPage => RenderType == TabRenderType.WebRender && !IsStartPage;
    public static TabKind Web { get; } = new("New tab", TabRenderType.WebRender, null, "globe");
    public static TabKind StartPage { get; } = new("Start Page", TabRenderType.UiNative, null, "flag.fill", true);

    /// <summary>The content of each native view this build knows, titled and drawn as the
    /// view is.</summary>
    private static readonly IReadOnlyDictionary<NativeView, TabKind> Views = NativeView.All.ToDictionary(view => view,
        view => new TabKind(view.Title, TabRenderType.UiNative, view.Name, view.Symbol));

    #endregion

    #region Constructors

    private TabKind(string name, TabRenderType renderType, string? nativeKind, string symbol, bool isStartPage = false) {
        Name = name;
        RenderType = renderType;
        NativeKind = nativeKind;
        Symbol = symbol;
        IsStartPage = isStartPage;
    }

    #endregion

    #region Actions - Content decoding

    /// <summary>The content of a tab that shows `view`.</summary>
    public static TabKind Of(NativeView view) => Views[view];

    public static TabKind Native(string kind, string title, string symbol = "square") {
        ArgumentException.ThrowIfNullOrWhiteSpace(kind);
        return NativeView.Named(kind) is { } view
            ? Of(view)
            : new(string.IsNullOrWhiteSpace(title) ? "Native Tab" : title, TabRenderType.UiNative, kind, symbol);
    }

    public static TabKind FromStored(string? nativeKind, string? url, string title)
        => nativeKind is { } kind ? Native(kind, title) : url is null ? StartPage : Web;

    #endregion

    #region Mutators

    public string Title(string? url) => IsWebPage ? url ?? "New tab" : Name;

    #endregion
}
