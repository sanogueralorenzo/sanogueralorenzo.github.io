namespace CrestCore.Contracts;

/// Which password manager or browser wrote a password file, as its headers
/// tell: a Bitwarden export names `login_uri`, a Firefox one a realm, form
/// origin or guid, a Safari one a one-time code, and any other is a browser's
/// own. A format travels as its index in `All`, so `All` is append-only.
public sealed class CredentialFileFormat {
    #region Static Variables

    public static readonly CredentialFileFormat Browser = new(name: "browser", title: "Browser CSV", markers: [], precedence: 3);
    public static readonly CredentialFileFormat Firefox = new(name: "firefox", title: "Firefox CSV",
        markers: ["httprealm", "formactionorigin", "guid"], precedence: 1);
    public static readonly CredentialFileFormat Safari = new(name: "safari", title: "Safari CSV", markers: ["otpauth", "otp_auth"],
        precedence: 2);
    public static readonly CredentialFileFormat Bitwarden = new(name: "bitwarden", title: "Bitwarden CSV", markers: ["login_uri"],
        precedence: 0);

    public static IReadOnlyList<CredentialFileFormat> All { get; } = [Browser, Firefox, Safari, Bitwarden];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the import review calls the file.
    [Localized]
    public string Title { get; }

    /// The headers, as a file's headers read once normalized, that only this
    /// format writes. A format without any is the one a file is when no other
    /// format's header appears.
    private readonly IReadOnlyList<string> markers;
    /// Which format a file is taken for first when its headers name several:
    /// the lowest.
    private readonly int precedence;

    #endregion

    #region Constructors

    private CredentialFileFormat(string name, string title, IReadOnlyList<string> markers, int precedence) {
        Name = name;
        Title = title;
        this.markers = markers;
        this.precedence = precedence;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialFileFormat? Named(string? name) => All.FirstOrDefault(format => format.Name == name);

    /// The format a file whose normalized headers are `headers` is.
    public static CredentialFileFormat Detected(IReadOnlySet<string> headers) {
        ArgumentNullException.ThrowIfNull(headers);
        return All.OrderBy(format => format.precedence).First(format => format.markers.Count == 0 || format.markers.Any(headers.Contains));
    }

    #endregion
}
