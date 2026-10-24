using System.Globalization;
using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A web address an import keeps: an http or https address with a host, as
/// the Apple platforms' URL parser reads the spelling another browser stored,
/// without credentials, and without its fragment where the import drops it.
///
/// The reading follows that parser exactly, because a Crest browser-data file
/// written by either side must read back identically on both. A component
/// holding a character it does not allow, or a `%` that starts no escape, is
/// escaped whole, `%` included; one that is already valid is kept as spelled.
/// A host is read with its escapes undone, and one that is not ASCII is
/// written in its IDNA form; one holding a character a host cannot hold reads
/// as no address. A port loses its leading zeros, and an empty one is dropped.
internal readonly record struct ImportAddress {
    #region Static Variables

    /// The longest spelling an import keeps, in characters.
    public const int MaximumLength = 8_192;

    private const string Hex = "0123456789ABCDEF";
    private const string SubDelimiters = "!$&'()*+,;=";

    private static readonly IdnMapping Idna = new() { AllowUnassigned = true, UseStd3AsciiRules = false };

    #endregion

    #region Variables

    /// The address as the import keeps it.
    public string Spelling { get; }

    #endregion

    #region Constructors

    private ImportAddress(string spelling) => Spelling = spelling;

    #endregion

    #region Actions - Reading

    /// The address `source` spells, with its scheme in lowercase, or null when
    /// it is not an http or https address with a host.
    public static ImportAddress? Read(string? source, bool removesFragment = false) =>
        Parsed(source, lowercasesScheme: true, removesFragment);

    /// The address a Crest browser-data file spells, which must already be
    /// spelled as an import keeps it: null for no address, and `Invalid` for a
    /// spelling that reads differently.
    public static bool TryReadStored(string? source, bool removesFragment, out ImportAddress? address) {
        address = null;
        if (source is null) return true;
        address = Parsed(source, lowercasesScheme: false, removesFragment);
        return address?.Spelling == source;
    }

    /// The address as a Crest browser-data file writes it: read again without
    /// credentials, and without its fragment where `removesFragment`, or null
    /// when it is not an http or https address with a host.
    public static string? Written(string? source, bool removesFragment) =>
        Parsed(source, lowercasesScheme: false, removesFragment)?.Spelling;

    /// The host, which an unnamed tab takes as its title; an IP literal
    /// without its brackets and with its escapes undone.
    public string Host {
        get {
            int start = Spelling.IndexOf("://", StringComparison.Ordinal) + 3;
            int end = start;
            while (end < Spelling.Length && Spelling[end] is not ('/' or '?' or '#')) end++;
            string authority = Spelling[start..end];
            if (authority.StartsWith('[')) return Uri.UnescapeDataString(authority[1..authority.IndexOf(']', StringComparison.Ordinal)]);
            int colon = authority.LastIndexOf(':');
            return colon < 0 ? authority : authority[..colon];
        }
    }

    /// The scheme, as spelled.
    public string Scheme => Spelling[..Spelling.IndexOf("://", StringComparison.Ordinal)];

    /// The port the address names, or null when it names none; one too large
    /// for any port reads as `int.MaxValue`.
    public int? Port {
        get {
            int start = Spelling.IndexOf("://", StringComparison.Ordinal) + 3;
            int end = start;
            while (end < Spelling.Length && Spelling[end] is not ('/' or '?' or '#')) end++;
            string authority = Spelling[start..end];
            int hostEnd = authority.StartsWith('[') ? authority.IndexOf(']', StringComparison.Ordinal) + 1 : 0;
            int colon = authority.IndexOf(':', hostEnd);
            if (colon < 0) return null;
            string digits = authority[(colon + 1)..];
            return digits.Length > 9 ? int.MaxValue : int.Parse(digits, CultureInfo.InvariantCulture);
        }
    }

    private static ImportAddress? Parsed(string? source, bool lowercasesScheme, bool removesFragment) {
        if (source is null || new StringInfo(source).LengthInTextElements > MaximumLength) return null;
        int colon = source.IndexOf(':', StringComparison.Ordinal);
        if (colon <= 0 || !IsScheme(source.AsSpan(0, colon))) return null;
        string scheme = source[..colon];
        string lowered = scheme.ToLowerInvariant();
        if (WebScheme.Named(lowered) is null) return null;
        string rest = source[(colon + 1)..];
        if (!rest.StartsWith("//", StringComparison.Ordinal)) return null;
        rest = rest[2..];

        int fragmentStart = rest.IndexOf('#', StringComparison.Ordinal);
        string? fragment = fragmentStart < 0 ? null : rest[(fragmentStart + 1)..];
        if (fragmentStart >= 0) rest = rest[..fragmentStart];
        int queryStart = rest.IndexOf('?', StringComparison.Ordinal);
        string? query = queryStart < 0 ? null : rest[(queryStart + 1)..];
        if (queryStart >= 0) rest = rest[..queryStart];
        int pathStart = rest.IndexOf('/', StringComparison.Ordinal);
        string authority = pathStart < 0 ? rest : rest[..pathStart];
        string path = pathStart < 0 ? "" : rest[pathStart..];

        int at = authority.LastIndexOf('@');
        string hostAndPort = at < 0 ? authority : authority[(at + 1)..];
        if (!TrySplitHost(hostAndPort, out string rawHost, out string? port)) return null;
        string? host = HostSpelling(rawHost);
        if (string.IsNullOrEmpty(host)) return null;

        var spelling = new StringBuilder(source.Length + 16);
        spelling.Append(lowercasesScheme ? lowered : scheme).Append("://").Append(host);
        if (!string.IsNullOrEmpty(port)) spelling.Append(':').Append(port);
        spelling.Append(Component(path, AllowsInPath));
        if (query is not null) spelling.Append('?').Append(Component(query, AllowsInQuery));
        if (fragment is not null && !removesFragment) spelling.Append('#').Append(Component(fragment, AllowsInQuery));
        return new ImportAddress(spelling.ToString());
    }

    #endregion

    #region Actions - Components

    private static bool IsScheme(ReadOnlySpan<char> scheme) {
        if (!char.IsAsciiLetter(scheme[0])) return false;
        foreach (char character in scheme)
            if (!char.IsAsciiLetterOrDigit(character) && character is not ('+' or '-' or '.')) return false;
        return true;
    }

    /// The host and the port's digits without leading zeros. False when the
    /// port holds anything but digits.
    private static bool TrySplitHost(string hostAndPort, out string host, out string? port) {
        port = null;
        host = hostAndPort;
        int closing = hostAndPort.StartsWith('[') ? hostAndPort.IndexOf(']', StringComparison.Ordinal) : -1;
        int colon = hostAndPort.IndexOf(':', closing < 0 ? 0 : closing);
        if (hostAndPort.StartsWith('[') && closing < 0) return false;
        if (colon < 0) {
            if (closing >= 0 && closing != hostAndPort.Length - 1) return false;
            return true;
        }
        if (closing >= 0 && colon != closing + 1) return false;
        host = hostAndPort[..colon];
        string digits = hostAndPort[(colon + 1)..];
        if (!digits.All(char.IsAsciiDigit)) return false;
        string trimmed = digits.TrimStart('0');
        port = digits.Length == 0 ? null : trimmed.Length == 0 ? "0" : trimmed;
        return true;
    }

    /// The host as a URL keeps it, or null for one a host cannot be.
    private static string? HostSpelling(string raw) {
        if (raw.StartsWith('[')) return raw;
        if (!TryUnescape(raw, out string? decoded)) return null;
        foreach (char character in decoded)
            if (character < 0x80 && !char.IsAsciiLetterOrDigit(character) && character is not ('-' or '.' or '_' or '~')
                && !SubDelimiters.Contains(character, StringComparison.Ordinal))
                return null;
        bool ascii = decoded.All(char.IsAscii);
        try {
            if (ascii) {
                bool encoded = decoded.Split('.').Any(label => label.StartsWith("xn--", StringComparison.OrdinalIgnoreCase));
                if (encoded) _ = Idna.GetUnicode(decoded);
                return decoded;
            }
            return Idna.GetAscii(decoded);
        } catch (ArgumentException) {
            return null;
        }
    }

    /// `raw` with its escapes undone as UTF-8. False when an escape is
    /// malformed or the bytes are not UTF-8.
    private static bool TryUnescape(string raw, out string decoded) {
        decoded = raw;
        if (!raw.Contains('%', StringComparison.Ordinal)) return true;
        var bytes = new List<byte>(raw.Length);
        int literal = 0;
        for (int index = 0; index < raw.Length; index++) {
            if (raw[index] != '%') continue;
            if (index + 2 >= raw.Length || !IsHex(raw[index + 1]) || !IsHex(raw[index + 2])) return false;
            bytes.AddRange(Encoding.UTF8.GetBytes(raw[literal..index]));
            bytes.Add(Convert.ToByte(raw.Substring(index + 1, 2), 16));
            index += 2;
            literal = index + 1;
        }
        bytes.AddRange(Encoding.UTF8.GetBytes(raw[literal..]));
        try {
            decoded = new UTF8Encoding(false, throwOnInvalidBytes: true).GetString([.. bytes]);
            return true;
        } catch (DecoderFallbackException) {
            return false;
        }
    }

    /// The component as spelled when it is valid, else escaped whole.
    private static string Component(string component, Func<char, bool> allows) {
        if (IsValid(component, allows)) return component;
        var escaped = new StringBuilder(component.Length * 3);
        foreach (byte value in Encoding.UTF8.GetBytes(component)) {
            if (value < 0x80 && value != '%' && allows((char)value)) escaped.Append((char)value);
            else escaped.Append('%').Append(Hex[value >> 4]).Append(Hex[value & 0xF]);
        }
        return escaped.ToString();
    }

    private static bool IsValid(string component, Func<char, bool> allows) {
        for (int index = 0; index < component.Length; index++) {
            char character = component[index];
            if (character == '%') {
                if (index + 2 >= component.Length || !IsHex(component[index + 1]) || !IsHex(component[index + 2])) return false;
                index += 2;
            } else if (character >= 0x80 || !allows(character)) {
                return false;
            }
        }
        return true;
    }

    private static bool IsHex(char character) => char.IsAsciiHexDigit(character);

    private static bool IsPathCharacter(char character) => char.IsAsciiLetterOrDigit(character)
        || character is '-' or '.' or '_' or '~' or ':' or '@' || SubDelimiters.Contains(character, StringComparison.Ordinal);

    private static bool AllowsInPath(char character) => character == '/' || IsPathCharacter(character);

    private static bool AllowsInQuery(char character) => character is '/' or '?' || IsPathCharacter(character);

    #endregion
}
