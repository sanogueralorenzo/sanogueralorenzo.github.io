namespace CrestCore.Contracts;

/// A text field a download record validates, and the longest value it holds.
///
/// A field travels as its index in `All`, so `All` is append-only.
public sealed class DownloadTextField {
    #region Variables

    public static readonly DownloadTextField Filename = new(name: "filename", maximumLength: 1_024);
    public static readonly DownloadTextField Destination = new(name: "destination", maximumLength: 8_192);
    public static readonly DownloadTextField Message = new(name: "message", maximumLength: 2_048);
    public static readonly DownloadTextField MimeType = new(name: "mimeType", maximumLength: 255);

    public static IReadOnlyList<DownloadTextField> All { get; } = [Filename, Destination, Message, MimeType];

    public string Name { get; }
    public int MaximumLength { get; }

    #endregion

    #region Constructors

    private DownloadTextField(string name, int maximumLength) {
        Name = name;
        MaximumLength = maximumLength;
    }

    #endregion

    #region Actions - Validation

    /// Refuses an empty value or one longer than the field holds.
    public void Validate(string? value) {
        if (string.IsNullOrEmpty(value) || value.Length > MaximumLength) throw new Rejected(new InvalidDownloadText(this));
    }

    #endregion

    #region Actions - Lookup

    public static DownloadTextField? Named(string? name) => All.FirstOrDefault(field => field.Name == name);

    #endregion
}
