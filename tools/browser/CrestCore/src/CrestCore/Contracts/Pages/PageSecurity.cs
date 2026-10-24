namespace CrestCore.Contracts;

/// How far the engine trusts the connection of the document a page shows, and
/// what Crest tells the person about it. A level travels as its index in
/// `All`, so `All` is append-only.
public sealed class PageSecurity {
    #region Static Variables

    /// Nothing to judge: no document yet, a local or internal page, or a load
    /// that failed before a connection was made.
    public static readonly PageSecurity None = new(name: "none", title: "Not Secure", symbol: "lock.open.fill");

    /// A document delivered without transport security, such as plain HTTP.
    public static readonly PageSecurity Insecure = new(name: "insecure", title: "Not Secure", symbol: "lock.open.fill");

    /// A verified TLS connection with no insecure content.
    public static readonly PageSecurity Secure = new(name: "secure", title: "Secure", symbol: "lock.fill", isSecure: true);

    /// A verified TLS connection whose document also shows or runs content
    /// that was not delivered securely.
    public static readonly PageSecurity MixedContent = new(name: "mixed_content", title: "Partly Secure",
        symbol: "lock.trianglebadge.exclamationmark.fill", detail: "Some content on this page was not delivered securely.");

    /// The site's certificate is not trusted: the engine's warning page, or a
    /// page reached past it.
    public static readonly PageSecurity CertificateError = new(name: "certificate_error", title: "Certificate Not Trusted",
        symbol: "exclamationmark.lock.fill",
        detail: "This site’s certificate is not trusted. Information you send could be read by others.", isHazardous: true);

    /// The engine flagged the page itself as malicious or deceptive.
    public static readonly PageSecurity Dangerous = new(name: "dangerous", title: "Dangerous Site",
        symbol: "exclamationmark.octagon.fill", detail: "This site may try to harm your Mac or steal your information.",
        isHazardous: true);

    public static IReadOnlyList<PageSecurity> All { get; } = [None, Insecure, Secure, MixedContent, CertificateError, Dangerous];

    #endregion

    #region Variables

    /// The spelling an engine host reports the level in.
    public string Name { get; }

    /// What the site controls call the connection.
    [Localized]
    public string Title { get; }

    /// The SF Symbol shown beside the title.
    public string Symbol { get; }

    /// What the site controls add about the connection, when there is more to
    /// say than its title.
    [Localized]
    public string? Detail { get; }

    /// A verified connection that delivered everything securely.
    public bool IsSecure { get; }

    /// The page may put the person at risk, beyond having no secure connection.
    public bool IsHazardous { get; }

    #endregion

    #region Constructors

    private PageSecurity(string name, string title, string symbol, string? detail = null, bool isSecure = false,
        bool isHazardous = false) {
        Name = name;
        Title = title;
        Symbol = symbol;
        Detail = detail;
        IsSecure = isSecure;
        IsHazardous = isHazardous;
    }

    #endregion

    #region Actions - Lookup

    public static PageSecurity? Named(string? name) => All.FirstOrDefault(security => security.Name == name);

    #endregion
}
