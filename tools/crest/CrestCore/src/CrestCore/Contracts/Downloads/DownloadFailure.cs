namespace CrestCore.Contracts;

/// Why a download stopped before its file was saved, in the words its row
/// shows the person. An engine's own description, when it has one, travels
/// beside it as the record's message.
///
/// A failure travels as its index in `All`, so `All` is append-only.
public sealed class DownloadFailure {
    #region Variables

    public static readonly DownloadFailure Interrupted = new(name: "interrupted", message: "The download was interrupted.");
    public static readonly DownloadFailure Network = new(name: "network",
        message: "The download stopped because of a network problem.");
    public static readonly DownloadFailure Server = new(name: "server", message: "The server couldn’t provide the file.");
    public static readonly DownloadFailure NoSpace = new(name: "noSpace", message: "There isn’t enough disk space to save the file.");
    public static readonly DownloadFailure FileAccess = new(name: "fileAccess", message: "The file couldn’t be saved in its folder.");
    public static readonly DownloadFailure FolderUnavailable = new(name: "folderUnavailable",
        message: "The download folder is unavailable. Choose another folder in Space settings.");
    public static readonly DownloadFailure BlockedUnsafe = new(name: "blockedUnsafe",
        message: "This download was blocked because it could harm your computer.");
    public static readonly DownloadFailure BlockedInsecure = new(name: "blockedInsecure",
        message: "This download was blocked because it came over an insecure connection.");
    public static readonly DownloadFailure BlockedByPolicy = new(name: "blockedByPolicy",
        message: "This download was blocked by a safety or organization policy.");

    public static IReadOnlyList<DownloadFailure> All { get; } =
        [Interrupted, Network, Server, NoSpace, FileAccess, FolderUnavailable, BlockedUnsafe, BlockedInsecure, BlockedByPolicy];

    public string Name { get; }

    /// What the download's row tells the person.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private DownloadFailure(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static DownloadFailure? Named(string? name) => All.FirstOrDefault(failure => failure.Name == name);

    #endregion
}
