using System.Net;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A search address with exactly one `%s` or `{searchTerms}` placeholder for
/// what a person searches for. A built-in's address may also spell slots its
/// options fill; one a person types holds only the placeholder and passes the
/// rules every custom provider follows. A template renders a query once into
/// its placeholder, and options edit it into the address a provider searches.
internal sealed record SearchTemplate(string Pattern) {
    #region Static Variables

    public const int MaximumLength = 2048;
    private const string PercentPlaceholder = "%s";
    private const string OpenSearchPlaceholder = "{searchTerms}";
    private const string ProbeMarker = "crest-template-probe";

    private static readonly string[] SecretParameters =
        ["token", "key", "apikey", "api_key", "access_token", "password", "credential", "credentials", "auth", "authorization"];

    #endregion

    #region Variables

    /// The host the template searches, lowercased and without `www.`, or
    /// empty when it names none.
    public string Host => Uri.TryCreate(Probe(Pattern), UriKind.Absolute, out var uri) ? WithoutWww(uri.Host.ToLowerInvariant()) : "";

    #endregion

    #region Actions - Rendering

    /// The address for `query`, percent-encoded as UTF-8 with only RFC 3986
    /// unreserved characters left bare, written once into the placeholder, so
    /// a query that spells a placeholder stays text.
    public string Render(string query) {
        ArgumentNullException.ThrowIfNull(query);
        string encoded = Uri.EscapeDataString(query);
        int index = Pattern.IndexOf(PercentPlaceholder, StringComparison.Ordinal);
        int length = PercentPlaceholder.Length;
        if (index < 0) {
            index = Pattern.IndexOf(OpenSearchPlaceholder, StringComparison.Ordinal);
            length = OpenSearchPlaceholder.Length;
        }
        return index < 0 ? Pattern : string.Concat(Pattern.AsSpan(0, index), encoded, Pattern.AsSpan(index + length));
    }

    #endregion

    #region Actions - Editing

    /// This template with each of `edits` made, then every slot no edit
    /// filled holding its provider's default.
    public SearchTemplate Edited(IEnumerable<SearchEdit> edits, IEnumerable<SearchSlotDefault> defaults) {
        var edited = edits.Aggregate(this, (template, edit) => edit.Applied(template));
        return defaults.Aggregate(edited, (template, slot) => template.Filling(slot.Slot, slot.Value));
    }

    /// This template with the query parameter `name` set to `value`, in
    /// place of its own value for it or after its other parameters.
    public SearchTemplate Setting(string name, string value) {
        int fragment = Pattern.IndexOf('#', StringComparison.Ordinal);
        string address = fragment < 0 ? Pattern : Pattern[..fragment];
        string rest = fragment < 0 ? "" : Pattern[fragment..];
        int query = address.IndexOf('?', StringComparison.Ordinal);
        if (query < 0) return new($"{address}?{name}={value}{rest}");
        var parameters = address[(query + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries).ToList();
        int existing = parameters.FindIndex(parameter => parameter.Split('=')[0] == name);
        if (existing >= 0) parameters[existing] = $"{name}={value}";
        else parameters.Add($"{name}={value}");
        return new($"{address[..(query + 1)]}{string.Join('&', parameters)}{rest}");
    }

    /// This template with `slot` holding `value`.
    public SearchTemplate Filling(SearchSlot slot, string value) => new(Pattern.Replace(slot.Token, value, StringComparison.Ordinal));

    #endregion

    #region Actions - Validation

    /// `value` trimmed and checked as an address a person typed for a
    /// provider: HTTPS on a public host and the standard port, exactly one
    /// placeholder outside the fragment, no credentials, secrets or stray
    /// percent signs, at most `MaximumLength` characters. Throws `Rejected`
    /// with `InvalidSearchEngine` naming the first flaw found.
    public static SearchTemplate Admit(string value) {
        ArgumentNullException.ThrowIfNull(value);
        value = value.Trim();
        if (value.Length > MaximumLength) throw Flawed(SearchEngineFlaw.TemplateTooLong);
        int count = Occurrences(value, PercentPlaceholder) + Occurrences(value, OpenSearchPlaceholder);
        if (count == 0) throw Flawed(SearchEngineFlaw.MissingPlaceholder);
        if (count != 1) throw Flawed(SearchEngineFlaw.AmbiguousPlaceholder);
        for (int i = 0; i < value.Length; i++) {
            if (value[i] != '%') continue;
            if (i + 1 < value.Length && value[i + 1] == 's') {
                i++;
                continue;
            }
            if (i + 2 >= value.Length || !Uri.IsHexDigit(value[i + 1]) || !Uri.IsHexDigit(value[i + 2]))
                throw Flawed(SearchEngineFlaw.InvalidTemplate);
            i += 2;
        }
        string probe = Probe(value);
        // A template without a scheme is an HTTPS omission, not a malformed URL.
        if (!Uri.TryCreate(probe, UriKind.Absolute, out var uri) || uri.IsFile)
            throw Flawed(probe.Contains("://", StringComparison.Ordinal) ? SearchEngineFlaw.InvalidTemplate : SearchEngineFlaw.RequiresHttps);
        if (WebScheme.Named(uri.Scheme) is not { IsSecure: true } scheme) throw Flawed(SearchEngineFlaw.RequiresHttps);
        if (uri.Host.Length == 0) throw Flawed(SearchEngineFlaw.InvalidTemplate);
        if (uri.UserInfo.Length != 0) throw Flawed(SearchEngineFlaw.CredentialsInTemplate);
        if (uri.Port != scheme.DefaultPort) throw Flawed(SearchEngineFlaw.NonstandardPort);
        if (!IsPublicHost(uri.Host)) throw Flawed(SearchEngineFlaw.UnsafeHost);
        if (uri.Fragment.Contains(ProbeMarker, StringComparison.Ordinal)) throw Flawed(SearchEngineFlaw.PlaceholderInFragment);
        foreach (string parameter in uri.Query.TrimStart('?').Split('&'))
            if (SecretParameters.Contains(Uri.UnescapeDataString(parameter.Split('=')[0]), StringComparer.OrdinalIgnoreCase))
                throw Flawed(SearchEngineFlaw.SecretInTemplate);
        return new(value);
    }

    /// `value` trimmed as an optional template: null when blank, else admitted.
    public static SearchTemplate? AdmitOptional(string? value) => string.IsNullOrWhiteSpace(value) ? null : Admit(value);

    private static Rejected Flawed(SearchEngineFlaw flaw) => new(new InvalidSearchEngine(flaw));

    /// The template with its placeholder spelled as a word, so it parses as an address.
    private static string Probe(string value) => value.Replace(PercentPlaceholder, ProbeMarker, StringComparison.Ordinal)
        .Replace(OpenSearchPlaceholder, ProbeMarker, StringComparison.Ordinal);

    /// A named public host: never local, numeric, or the query itself.
    private static bool IsPublicHost(string host) =>
        host.Contains('.') && !host.Contains(':')
        && !host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
        && !host.Equals("localhost", StringComparison.OrdinalIgnoreCase)
        && !host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase)
        && !host.Contains(ProbeMarker, StringComparison.OrdinalIgnoreCase)
        && !IPAddress.TryParse(host.Trim('[', ']'), out _);

    private static int Occurrences(string value, string placeholder) {
        int count = 0;
        for (int index = value.IndexOf(placeholder, StringComparison.Ordinal); index >= 0;
            index = value.IndexOf(placeholder, index + placeholder.Length, StringComparison.Ordinal)) count++;
        return count;
    }

    private static string WithoutWww(string host) => host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;

    #endregion
}
