namespace CrestCore.Domain;

/// A fixed built-in address with a single query placeholder.
internal sealed record SearchTemplate(string Pattern) {
    #region Variables

    public string Host {
        get {
            if (!Uri.TryCreate(Pattern.Replace("%s", "crest", StringComparison.Ordinal), UriKind.Absolute, out var uri)) return "";
            string host = uri.Host;
            return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
        }
    }

    #endregion

    #region Actions - Rendering

    /// Encode the query once so placeholders and URL punctuation remain text.
    public string Render(string query) {
        ArgumentNullException.ThrowIfNull(query);
        int index = Pattern.IndexOf("%s", StringComparison.Ordinal);
        return string.Concat(Pattern.AsSpan(0, index), Uri.EscapeDataString(query), Pattern.AsSpan(index + 2));
    }

    #endregion
}
