namespace CrestCore.Contracts;

/// A scheme the web serves pages over, with the port a URL of the scheme means
/// when it names none and whether it is secure. An address is a web address
/// exactly when `Named` knows its scheme. An origin of any other scheme keeps
/// the port it was given. A scheme travels as its index in `All`, so `All` is
/// append-only.
public sealed class WebScheme {
    #region Static Variables

    public static readonly WebScheme Http = new(name: "http", defaultPort: 80, isSecure: false);
    public static readonly WebScheme Https = new(name: "https", defaultPort: 443, isSecure: true);

    public static IReadOnlyList<WebScheme> All { get; } = [Http, Https];

    #endregion

    #region Variables

    /// The scheme as a URL spells it, in lowercase.
    public string Name { get; }

    /// The port a URL of the scheme means when it names none.
    public int DefaultPort { get; }

    /// The connection is encrypted and authenticated, so the page is a secure
    /// context and its credentials may be captured and offered.
    public bool IsSecure { get; }

    #endregion

    #region Constructors

    private WebScheme(string name, int defaultPort, bool isSecure) {
        Name = name;
        DefaultPort = defaultPort;
        IsSecure = isSecure;
    }

    #endregion

    #region Actions - Lookup

    public static WebScheme? Named(string? name) => All.FirstOrDefault(scheme => scheme.Name == name);

    /// The scheme `scheme` spells in any letter case, as a URL may.
    public static WebScheme? Spelled(string? scheme) => Named(scheme?.ToLowerInvariant());

    #endregion
}
