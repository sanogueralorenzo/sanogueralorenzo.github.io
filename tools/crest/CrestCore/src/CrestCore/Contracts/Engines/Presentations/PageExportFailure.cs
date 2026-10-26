namespace CrestCore.Contracts;

/// Why a page's export made no document, as the person reads it. A failure
/// travels as its index in `All`, so `All` is append-only.
public sealed class PageExportFailure {
    #region Static Variables

    public static readonly PageExportFailure Busy = new(name: "busy", message: "An export is already in progress for this page.");
    public static readonly PageExportFailure Unsupported = new(name: "unsupported", message: "This page cannot be exported.");
    public static readonly PageExportFailure Closed = new(name: "closed", message: "The page was closed.");
    public static readonly PageExportFailure Navigated = new(name: "navigated",
        message: "The page navigated before its export finished.");
    public static readonly PageExportFailure RendererStopped = new(name: "rendererStopped", message: "The page renderer stopped.");
    public static readonly PageExportFailure TimedOut = new(name: "timedOut", message: "The page export timed out.");
    public static readonly PageExportFailure TooLarge = new(name: "tooLarge", message: "The page export is too large.");
    public static readonly PageExportFailure Failed = new(name: "failed", message: "The page could not be exported.");

    public static IReadOnlyList<PageExportFailure> All { get; } =
        [Busy, Unsupported, Closed, Navigated, RendererStopped, TimedOut, TooLarge, Failed];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person is told about the export.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private PageExportFailure(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static PageExportFailure? Named(string? name) => All.FirstOrDefault(failure => failure.Name == name);

    #endregion
}
