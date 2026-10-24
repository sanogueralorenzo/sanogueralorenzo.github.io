namespace CrestCore.Contracts;

/// What the platform knows about a download before its risk is judged.
///
/// `SanitizedFilename` is the platform's file-system-safe name. The three type
/// facts come from the platform's type registry: whether the filename's
/// extension and the declared MIME type name code-running types, and whether
/// the two types are related (null when either type is unknown).
public sealed record DownloadRiskFacts(string SuggestedFilename, string SanitizedFilename, string? MimeType,
    bool ExtensionRunsCode, bool MimeTypeRunsCode, bool? TypesRelated) {
    #region Variables

    /// Extensions and MIME types that install or run software even when the
    /// platform's type registry does not say so.
    private static readonly HashSet<string> CodeRunningExtensions = new(StringComparer.Ordinal) {
        "app", "application", "bat", "bin", "cmd", "com", "command", "csh", "dmg",
        "exe", "jar", "ksh", "mobileconfig", "mpkg", "msi", "pkg", "ps1", "reg",
        "run", "scpt", "scr", "sh", "tool", "vbs", "workflow", "zsh"
    };

    private static readonly HashSet<string> CodeRunningMimeTypes = new(StringComparer.Ordinal) {
        "application/x-apple-diskimage",
        "application/x-bat",
        "application/x-executable",
        "application/x-mach-binary",
        "application/x-msdownload",
        "application/x-msi",
        "application/x-powershell",
        "application/x-sh",
        "application/x-shellscript"
    };

    /// The platform's suggested name may be longer than the name it saves under.
    public static int MaximumSuggestedFilenameLength => DownloadTextField.Filename.MaximumLength * 4;

    /// The saved name's extension or the declared type installs or runs software.
    public bool RunsCode => ExtensionRunsCode || MimeTypeRunsCode || CodeRunningExtensions.Contains(SanitizedExtension)
        || MimeType is { } mime && CodeRunningMimeTypes.Contains(mime.ToLowerInvariant());

    /// The suggested name holds invisible or direction-changing characters,
    /// which can disguise its real extension, such as `photo.jpg<RLO>gpj.command`.
    public bool HasDeceptiveFilename => SuggestedFilename.EnumerateRunes().Any(rune => rune.Value == 0x061C
        || rune.Value is >= 0x200B and <= 0x200F || rune.Value is >= 0x202A and <= 0x202E
        || rune.Value is >= 0x2066 and <= 0x2069 || rune.Value == 0xFEFF);

    private string SanitizedExtension {
        get {
            int dot = SanitizedFilename.LastIndexOf('.');
            return dot > 0 && dot < SanitizedFilename.Length - 1 ? SanitizedFilename[(dot + 1)..].ToLowerInvariant() : "";
        }
    }

    #endregion

    #region Actions - Validation

    /// Refuses facts the ledger could not record. An absent or empty MIME type
    /// is not a fact, so only its length is checked.
    public void Validate() {
        DownloadTextField.Filename.Validate(SanitizedFilename);
        if (SuggestedFilename.Length > MaximumSuggestedFilenameLength) throw new Rejected(new InvalidDownloadText(DownloadTextField.Filename));
        if (!string.IsNullOrEmpty(MimeType)) DownloadTextField.MimeType.Validate(MimeType);
    }

    #endregion
}
