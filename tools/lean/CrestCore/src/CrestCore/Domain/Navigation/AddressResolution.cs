using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a typed or chosen address loads, and the rules every Space applies to
/// the addresses it holds.
public sealed record AddressResolution(string Url, string? SearchQuery) {
    #region Static Variables

    // Browser-owned URL spellings that are shared by address and tab rules.
    public const string AboutBlank = "about:blank";
    public const string ChromeScheme = "chrome";
    public const string CrestScheme = "crest";
    public const string ChromeExtensionScheme = "chrome-extension";
    public const string ChromePrefix = ChromeScheme + "://";
    public const string CrestPrefix = CrestScheme + "://";
    public const string ChromeExtensionPrefix = ChromeExtensionScheme + "://";

    /// The endings of names reserved for one device or one local network:
    /// loopback, multicast DNS, home networks and private use. No public
    /// certificate can name them.
    private static readonly string[] LocalNameEndings = [".localhost", ".local", ".home.arpa", ".internal"];

    #endregion

    #region Actions - Navigation

    /// The address a page loads for what the person typed or chose in a Space
    /// that searches with `provider`, on an engine that shows internal pages
    /// or not: an address as it is, or a search with the provider. Throws
    /// `Rejected` with `UnsupportedAddress` when the input names nothing a
    /// page can load, as blank input does.
    public static string Loading(string input, SearchProvider provider, bool allowsInternalPages) {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(provider);
        // The empty document is an address on every engine, whatever its fragment.
        var value = input.Trim();
        if (value == AboutBlank || value.StartsWith(AboutBlank + "#", StringComparison.Ordinal))
            return value;
        AddressResolution? resolution;
        try {
            resolution = Resolve(input, provider, allowsInternalPages);
        } catch (Rejected refused) when (refused.Rejection is UnsupportedAddress) {
            throw new Rejected(new UnsupportedAddress(input));
        }
        if (resolution is null || !Uri.TryCreate(resolution.Url, UriKind.Absolute, out _))
            throw new Rejected(new UnsupportedAddress(input));
        return resolution.Url;
    }

    /// `url` as it is, when it is an absolute address an engine loads for
    /// Crest itself: a held address is never a search, so no rule for typed
    /// input applies. Null when it is not one, or names an internal page an
    /// engine that shows none can't load.
    public static string? Held(string url, bool allowsInternalPages) {
        ArgumentNullException.ThrowIfNull(url);
        string value = url.Trim();
        if (IsInternalPage(value)) return allowsInternalPages ? value : null;
        return Uri.TryCreate(value, UriKind.Absolute, out var parsed)
            && UrlScheme.DispositionOf(parsed.Scheme, isAppInitiated: true) == ExternalSchemeDisposition.Engine
            ? value : null;
    }

    /// What `input` loads with `provider`, or null for blank input. Throws
    /// `Rejected` with `UnsupportedAddress` for input too long to be an
    /// address, or an internal page no Space may hold.
    public static AddressResolution? Resolve(string input, SearchProvider provider, bool allowsInternalPages = false) {
        string value = input.Trim();
        if (value.Length == 0) return null;
        if (value.Length > 4096) throw new Rejected(new UnsupportedAddress(value));
        if (value == AboutBlank || IsInternalPage(value)) {
            if (!allowsInternalPages) return new(provider.Search(value), value);
            ValidateUrl(value, allowsInternalPages: true);
            return new(value, null);
        }
        if (Uri.TryCreate(value, UriKind.Absolute, out var explicitUrl) && WebScheme.Named(explicitUrl.Scheme) is not null
            && explicitUrl.Host.Length > 0) return new(value, null);
        if (LocalFile(value) is { } localFile) return new(localFile, null);
        if (!value.Any(char.IsWhiteSpace) && Uri.TryCreate("http://" + value, UriKind.Absolute, out var typed) && typed.Host.Length > 0) {
            // As other browsers do, a host that only this network answers loads
            // over http, and any other dotted host over https.
            if (IsLocal(typed, value)) return new("http://" + value, null);
            if (value.Contains('.')) return new("https://" + value, null);
        }
        return new(provider.Search(value), value);
    }

    /// Whether `address`, read from `typed` without a scheme, names a host
    /// only this device or its network answers: an IPv6 address, which only
    /// brackets spell; an IPv4 address written out in full; `localhost`; or a
    /// name reserved for local networks. Short numbers such as `3.14` parse
    /// as IPv4 addresses but are not written as one.
    private static bool IsLocal(Uri address, string typed) {
        if (address.HostNameType == UriHostNameType.IPv6) return true;
        if (address.HostNameType == UriHostNameType.IPv4) return typed.StartsWith(address.Host, StringComparison.Ordinal);
        string host = address.Host.TrimEnd('.');
        return host.Equals("localhost", StringComparison.OrdinalIgnoreCase)
            || LocalNameEndings.Any(ending => host.EndsWith(ending, StringComparison.OrdinalIgnoreCase));
    }

    /// Whether `value` names one of the browser's own pages.
    private static bool IsInternalPage(string value) =>
        value.StartsWith(ChromePrefix, StringComparison.OrdinalIgnoreCase)
        || value.StartsWith(CrestPrefix, StringComparison.OrdinalIgnoreCase)
        || value.StartsWith(ChromeExtensionPrefix, StringComparison.OrdinalIgnoreCase);

    /// An explicit `file://` URL, or an absolute path the person typed. Only these
    /// three spellings reach a local document; everything else stays a search, and
    /// nothing here touches the file system, so the decision stays deterministic.
    private static string? LocalFile(string value) {
        string candidate = value;
        if (candidate.StartsWith('~')) {
            if (candidate.Length > 1 && candidate[1] != '/') return null;
            string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (home.Length == 0) return null;
            candidate = home.TrimEnd('/') + candidate[1..];
        } else if (!candidate.StartsWith('/') && !candidate.StartsWith("file:", StringComparison.OrdinalIgnoreCase)) {
            return null;
        }
        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var parsed) || parsed.Scheme != Uri.UriSchemeFile
            || parsed.UserInfo.Length > 0 || parsed.AbsolutePath.Length == 0) return null;
        if (parsed.Host.Length == 0) return parsed.AbsoluteUri;
        // `file://localhost/…` names this device the long way round; anything else
        // is a remote authority Crest does not read as a local document.
        if (!parsed.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)) return null;
        return new UriBuilder(parsed) { Host = string.Empty }.Uri.AbsoluteUri;
    }

    #endregion

    #region Actions - Validation

    /// Throws `Rejected` with `UnsupportedAddress` for an address no Space
    /// holds.
    public static void ValidateUrl(string? url, bool allowsInternalPages = false) {
        if (url is null || url.Length > 16384 || !Uri.TryCreate(url, UriKind.Absolute, out var parsed)
            || (WebScheme.Named(parsed.Scheme) is null
                && url != AboutBlank
                // A local document is a legitimate tab URL on every engine. It stays
                // out of sync, which the sync projection decides by scheme, not here.
                && !(parsed.Scheme == Uri.UriSchemeFile && parsed.Host.Length == 0 && parsed.AbsolutePath.Length > 0)
                && !(allowsInternalPages && (parsed.Scheme == ChromeScheme
                    || parsed.Scheme == CrestScheme) && parsed.Host.Length > 0)
                && !(allowsInternalPages && parsed.Scheme == ChromeExtensionScheme && parsed.Host.Length == 32
                    && parsed.Host.All(c => c is >= 'a' and <= 'p')))
            || !string.IsNullOrEmpty(parsed.UserInfo))
            throw new Rejected(new UnsupportedAddress(url ?? ""));
    }

    #endregion
}
