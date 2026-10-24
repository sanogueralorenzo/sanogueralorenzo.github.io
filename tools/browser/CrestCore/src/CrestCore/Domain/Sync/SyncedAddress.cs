using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// An address a synced tab or visit carries, as its record holds it.
///
/// The Apple clients read an address with Foundation's `URL(string:)`, which
/// percent-encodes the characters RFC 3986 does not allow and writes a
/// non-ASCII host in punycode, then take it when it is http or https and at
/// most `MaximumBytes` of UTF-8. Staging writes the canonical RFC 3986 spelling
/// every client parses to the same address, and only an http or https address
/// with a host that fits. Reading is lenient in the safe direction: a record
/// any client takes is never refused here, since refusing it would lose, on
/// this device alone, a record the others sync.
public readonly record struct SyncedAddress(string Text) {
    #region Static Variables

    /// The longest address, in UTF-8 bytes, every client reads in a record.
    public const int MaximumBytes = 8_192;

    /// Characters RFC 3986 allows in a host name besides letters and digits.
    private const string HostSymbols = "-._~!$&'()*+,;=";

    /// Characters RFC 3986 allows in a path segment besides letters and digits.
    private const string PathSymbols = "-._~!$&'()*+,;=:@";

    /// Characters RFC 3986 allows in a user name or password besides letters
    /// and digits; a colon only separates the two.
    private const string UserSymbols = "-._~!$&'()*+,;=";

    private static readonly IdnMapping Punycode = new();

    #endregion

    #region Variables

    /// The canonical RFC 3986 spelling every client parses to this address, or
    /// null when the address has no scheme, or a host or port no client reads.
    public string? Spelled => Parts() is { } parts ? parts.Spelled : null;

    /// Whether staging carries the address: http or https, with a host, and
    /// spelled in at most `MaximumBytes` of UTF-8.
    public bool IsPortable => Parts() is { IsWeb: true, Host.Length: > 0 } parts
        && Encoding.UTF8.GetByteCount(parts.Spelled) <= MaximumBytes;

    /// Whether this device sends the address in a web field of a record: http
    /// or https, spelled as every client parses it in at most `MaximumBytes`.
    public bool IsSendable => Parts() is { IsWeb: true } parts && Encoding.UTF8.GetByteCount(parts.Spelled) <= MaximumBytes;

    /// Whether a client may take the address in a web field of a record: http
    /// or https, and short enough that some client's spelling of it fits.
    /// Nothing else about it is checked, so an address any client takes is
    /// taken here too.
    public bool IsReadableWebAddress => IsWeb(Scheme(Text)) && ShortestSpelledBytes() <= MaximumBytes;

    #endregion

    #region Actions - Content

    // Shared browser records describe portable web content, never an engine's
    // internal pages, native documents, files, or extension execution state.

    /// Whether a record whose address is `url` is shared: an address every
    /// client reads is http or https, names a host and, spelled as every
    /// client parses it, fits in `MaximumBytes` of UTF-8; a record whose
    /// address does not stays on this device.
    public static bool Includes(string? url) => url is not null && new SyncedAddress(url).IsPortable;

    /// Whether a tab at `url`, saved at `savedUrl`, is shared: never a native
    /// document, and only when both its addresses are.
    public static bool IncludesTab(string? url, bool native, string? savedUrl)
        => !native && Includes(url) && (savedUrl is null || Includes(savedUrl));

    #endregion

    #region Actions - Parsing

    /// The address's parts, or null when it has no scheme or holds a host or
    /// port RFC 3986 does not allow.
    /// A component that holds only what RFC 3986 allows in it, escapes
    /// included, stays as it is; one that holds anything else is spelled
    /// whole, its `%` signs included, as clients spell text they parse.
    private (bool IsWeb, string Host, string Spelled)? Parts() {
        if (Scheme(Text) is not { } scheme) return null;
        string rest = Text[(scheme.Length + 1)..];
        bool changed = false;
        string Component(string text, string symbols) {
            if (IsAllowed(text, symbols)) return text;
            changed = true;
            return Escaped(text, symbols);
        }
        string authority = "", host = "";
        bool hasAuthority = rest.StartsWith("//", StringComparison.Ordinal);
        string? port = null;
        if (hasAuthority) {
            int end = rest.IndexOfAny(['/', '?', '#'], 2);
            string original = end < 0 ? rest[2..] : rest[2..end];
            rest = end < 0 ? "" : rest[end..];
            int at = original.LastIndexOf('@');
            if (at >= 0) {
                string userinfo = original[..at];
                int colon = userinfo.IndexOf(':');
                authority = colon < 0 ? Component(userinfo, UserSymbols)
                    : Component(userinfo[..colon], UserSymbols) + ":" + Component(userinfo[(colon + 1)..], UserSymbols);
                authority += "@";
            }
            string hostAndPort = original[(at + 1)..];
            int portColon = hostAndPort.StartsWith('[') ? hostAndPort.IndexOf(':', Math.Max(hostAndPort.IndexOf(']'), 0))
                : hostAndPort.LastIndexOf(':');
            if (portColon >= 0) {
                port = hostAndPort[(portColon + 1)..];
                hostAndPort = hostAndPort[..portColon];
            }
            if (port is not null && !port.All(char.IsAsciiDigit) || Host(hostAndPort) is not { } canonical) return null;
            host = canonical;
            changed |= host != hostAndPort;
        }
        int query = rest.IndexOf('?');
        int fragment = rest.IndexOf('#');
        if (query > fragment && fragment >= 0) query = -1;
        string path = rest[..(query >= 0 ? query : fragment >= 0 ? fragment : rest.Length)];
        if (!IsAllowed(path, PathSymbols + "/")) {
            // Without an authority, a colon in the first segment would read as
            // a scheme, so spelling it spells that segment's colons too.
            int firstSlash = hasAuthority ? 0 : path.IndexOf('/') is var slash && slash >= 0 ? slash : path.Length;
            path = Escaped(path[..firstSlash], PathSymbols.Replace(":", "", StringComparison.Ordinal) + "/")
                + Escaped(path[firstSlash..], PathSymbols + "/");
            changed = true;
        }
        string? queried = query >= 0 ? Component(rest[(query + 1)..(fragment >= 0 ? fragment : rest.Length)], PathSymbols + "/?") : null;
        string? fragmented = fragment >= 0 ? Component(rest[(fragment + 1)..], PathSymbols + "/?") : null;
        var spelled = new StringBuilder(scheme).Append(':');
        if (hasAuthority) {
            spelled.Append("//").Append(authority).Append(host);
            // An empty port reads as none; a spelling that changed anything leaves it out.
            if (port is { Length: > 0 } || port is not null && !changed) spelled.Append(':').Append(port);
        }
        spelled.Append(path);
        if (queried is not null) spelled.Append('?').Append(queried);
        if (fragmented is not null) spelled.Append('#').Append(fragmented);
        return (IsWeb(scheme), host, spelled.ToString());
    }

    /// The scheme `text` starts with, as RFC 3986 spells one, or null.
    private static string? Scheme(string text) {
        int colon = text.IndexOf(':');
        if (colon <= 0 || !char.IsAsciiLetter(text[0])) return null;
        for (int index = 1; index < colon; index++)
            if (!char.IsAsciiLetterOrDigit(text[index]) && text[index] is not ('+' or '-' or '.')) return null;
        return text[..colon];
    }

    private static bool IsWeb(string? scheme) => WebScheme.Spelled(scheme) is not null;

    /// A host as clients spell it: an IP literal as it is, a name in punycode
    /// when it is not ASCII, or null when it holds a character no host allows.
    private static string? Host(string host) {
        if (host.StartsWith('[')) return host.EndsWith(']') ? host : null;
        if (!host.All(char.IsAscii)) {
            try {
                host = Punycode.GetAscii(host);
            } catch (ArgumentException) {
                return null;
            }
        }
        for (int index = 0; index < host.Length; index++) {
            char character = host[index];
            if (char.IsAsciiLetterOrDigit(character) || HostSymbols.Contains(character)) continue;
            if (character == '%' && IsEscape(host, index)) continue;
            return null;
        }
        return host;
    }

    /// Whether `text` holds only letters, digits, `symbols` and escapes.
    private static bool IsAllowed(string text, string symbols) {
        for (int index = 0; index < text.Length; index++)
            if (!char.IsAsciiLetterOrDigit(text[index]) && !symbols.Contains(text[index]) && !(text[index] == '%' && IsEscape(text, index)))
                return false;
        return true;
    }

    /// `text` with every character but letters, digits and `symbols`, its `%`
    /// signs included, percent-encoded as UTF-8 in uppercase hex.
    private static string Escaped(string text, string symbols) {
        var result = new StringBuilder(text.Length * 3);
        for (int index = 0; index < text.Length; index++) {
            char character = text[index];
            if (char.IsAsciiLetterOrDigit(character) || symbols.Contains(character)) {
                result.Append(character);
                continue;
            }
            int length = char.IsSurrogatePair(text, index) ? 2 : 1;
            foreach (byte value in Encoding.UTF8.GetBytes(text.Substring(index, length)))
                result.Append('%').Append(value.ToString("X2", CultureInfo.InvariantCulture));
            index += length - 1;
        }
        return result.ToString();
    }

    /// Whether the `%` at `index` starts an escape: two hex digits follow it.
    private static bool IsEscape(string text, int index) =>
        index + 2 < text.Length && char.IsAsciiHexDigit(text[index + 1]) && char.IsAsciiHexDigit(text[index + 2]);

    /// The fewest UTF-8 bytes any client spells the address in: as it is, with
    /// a non-ASCII host in punycode when it has one. Spelling never shortens
    /// anything but a host.
    private int ShortestSpelledBytes() {
        int bytes = Encoding.UTF8.GetByteCount(Text);
        if (Scheme(Text) is not { } scheme || !Text.AsSpan(scheme.Length + 1).StartsWith("//")) return bytes;
        string rest = Text[(scheme.Length + 3)..];
        int end = rest.IndexOfAny(['/', '?', '#']);
        string authority = end < 0 ? rest : rest[..end];
        string host = authority[(authority.LastIndexOf('@') + 1)..];
        int colon = host.IndexOf(':');
        if (colon >= 0) host = host[..colon];
        if (host.All(char.IsAscii)) return bytes;
        try {
            return bytes - Encoding.UTF8.GetByteCount(host) + Encoding.UTF8.GetByteCount(Punycode.GetAscii(host));
        } catch (ArgumentException) {
            return bytes;
        }
    }

    #endregion
}
