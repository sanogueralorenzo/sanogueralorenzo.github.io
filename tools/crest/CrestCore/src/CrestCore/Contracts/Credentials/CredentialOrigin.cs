using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace CrestCore.Contracts;

/// The canonical HTTP(S) origin a credential belongs to. The platform
/// canonicalizes scheme, host and default port before it reaches the core, so
/// equality is exact member equality. The credential rules refuse an origin
/// that is not `IsValid`.
public sealed record CredentialOrigin(string Scheme, string Host, int Port) {
    #region Variables

    public const int MaximumHostLength = 1_024;

    /// An IP address host must be spelled as a page's origin spells it: IPv6
    /// compressed, with no zone ID, brackets or escapes, and IPv4 in dotted
    /// decimal.
    public bool IsValid => WebScheme.Named(Scheme) is not null && !string.IsNullOrEmpty(Host) && Host.Length <= MaximumHostLength
        && CanonicalHost(Host) == Host && Port is >= 1 and <= 65_535;

    public bool IsSecure => WebScheme.Named(Scheme)?.IsSecure == true;

    /// The origin as an address spells it: its scheme and host, an IPv6 host
    /// in brackets, and its port only where it is not the scheme's default.
    public string Spelling {
        get {
            string host = Host.Contains(':', StringComparison.Ordinal) ? $"[{Host}]" : Host;
            return WebScheme.Named(Scheme)?.DefaultPort == Port ? $"{Scheme}://{host}" : $"{Scheme}://{host}:{Port}";
        }
    }

    #endregion

    #region Actions - Capture

    /// Whether a frame at this origin under a top-level page at
    /// `topLevelOrigin` may capture and be offered credentials: both must be
    /// secure.
    internal bool IsSecureUnder(CredentialOrigin topLevelOrigin) {
        ArgumentNullException.ThrowIfNull(topLevelOrigin);
        return Validated().IsSecure && topLevelOrigin.Validated().IsSecure;
    }

    /// This origin, or the refusal of one that is not `IsValid`.
    internal CredentialOrigin Validated() => IsValid ? this : throw new Rejected(new InvalidCredentialOrigin());

    #endregion

    #region Actions - Host

    /// `host` as the URL standard spells it in a page's origin, so a saved
    /// password matches the page: an IPv6 address compressed, an IPv4 address
    /// in dotted decimal, and any other lowercase name as given. Null for a
    /// host with a colon that is no IPv6 address, or one ending in a number
    /// that is no IPv4 address; no page can have such a host.
    internal static string? CanonicalHost(string host) {
        ArgumentNullException.ThrowIfNull(host);
        if (host.Contains(':', StringComparison.Ordinal)) {
            // `IPAddress.TryParse` alone also takes brackets, a zone ID and an
            // embedded IPv4 address with leading zeros.
            bool spellsAddress = host.All(character => char.IsAsciiHexDigit(character) || character is ':' or '.')
                && HasDecimalIPv4Tail(host);
            return spellsAddress && IPAddress.TryParse(host, out var address) && address.AddressFamily == AddressFamily.InterNetworkV6
                ? IPv6Spelling(address.GetAddressBytes())
                : null;
        }
        string[] labels = host.Split('.');
        if (labels.Length > 1 && labels[^1].Length == 0) labels = labels[..^1];
        string last = labels[^1];
        bool endsInNumber = last.Length > 0 && last.All(char.IsAsciiDigit)
            || last.StartsWith("0x", StringComparison.OrdinalIgnoreCase) && last[2..].All(char.IsAsciiHexDigit);
        return endsInNumber ? IPv4Spelling(labels) : host;
    }

    /// Whether the IPv4 address an IPv6 address may end in is spelled as the
    /// URL standard requires: four decimal numbers up to 255, none with a
    /// leading zero.
    private static bool HasDecimalIPv4Tail(string host) {
        string tail = host[(host.LastIndexOf(':') + 1)..];
        if (!tail.Contains('.', StringComparison.Ordinal)) return true;
        string[] parts = tail.Split('.');
        return parts.Length == 4 && parts.All(part => part.Length is >= 1 and <= 3 && part.All(char.IsAsciiDigit)
            && (part.Length == 1 || part[0] != '0') && int.Parse(part, CultureInfo.InvariantCulture) <= 255);
    }

    /// The URL standard's IPv6 serialization: lowercase hexadecimal pieces,
    /// the first longest run of two or more zero pieces written as `::`, and
    /// never an embedded IPv4 address.
    private static string IPv6Spelling(byte[] bytes) {
        int[] pieces = [.. Enumerable.Range(0, 8).Select(index => bytes[2 * index] << 8 | bytes[2 * index + 1])];
        int compressed = -1;
        int longest = 1;
        for (int start = 0; start < pieces.Length; start++) {
            int length = 0;
            while (start + length < pieces.Length && pieces[start + length] == 0) length++;
            if (length > longest) (compressed, longest) = (start, length);
        }
        var spelling = new StringBuilder();
        for (int index = 0; index < pieces.Length; index++) {
            if (index == compressed) {
                spelling.Append(index == 0 ? "::" : ":");
                index += longest - 1;
                continue;
            }
            spelling.Append(pieces[index].ToString("x", CultureInfo.InvariantCulture));
            if (index < pieces.Length - 1) spelling.Append(':');
        }
        return spelling.ToString();
    }

    /// The URL standard's IPv4 parser: up to four parts, each decimal, octal
    /// after a leading zero or hexadecimal after `0x`, the last filling the
    /// bytes the others leave. Null when the parts are no IPv4 address.
    private static string? IPv4Spelling(string[] parts) {
        if (parts.Length > 4) return null;
        var numbers = new long[parts.Length];
        for (int index = 0; index < parts.Length; index++) {
            string digits = parts[index];
            if (digits.Length == 0) return null;
            int radix = 10;
            if (digits.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) (radix, digits) = (16, digits[2..]);
            else if (digits.Length > 1 && digits[0] == '0') (radix, digits) = (8, digits[1..]);
            foreach (char character in digits) {
                int digit = char.IsAsciiHexDigit(character) ? Convert.ToInt32(character.ToString(), 16) : radix;
                if (digit >= radix) return null;
                // Any value past 32 bits is refused below, so it stops growing there.
                numbers[index] = Math.Min(numbers[index] * radix + digit, 1L << 33);
            }
        }
        if (numbers[..^1].Any(number => number > 255) || numbers[^1] >= 1L << (8 * (5 - numbers.Length))) return null;
        long address = numbers[^1];
        for (int index = 0; index < numbers.Length - 1; index++) address += numbers[index] << (8 * (3 - index));
        return string.Create(CultureInfo.InvariantCulture, $"{address >> 24}.{address >> 16 & 255}.{address >> 8 & 255}.{address & 255}");
    }

    #endregion
}
