namespace CrestCore.Domain;

/// The language and region a device's platform reports, which a provider's
/// automatic language, region or store follows. Either is null where the
/// platform names none.
internal sealed record SearchLocale(string? Language, string? Region) {
    #region Static Variables

    /// A device whose platform has named no language or region yet.
    public static SearchLocale Unknown { get; } = new(Language: null, Region: null);

    #endregion

    #region Actions - Matching

    /// Whether `locale`, a locale identifier such as `de-AT` or `pt`, speaks
    /// this device's language.
    public bool Speaks(string locale) => Language is { Length: > 0 } language
        && string.Equals(LanguageOf(locale), language, StringComparison.OrdinalIgnoreCase);

    /// Whether `locale`, a locale identifier such as `en-GB`, or one of
    /// `regions` is this device's region.
    public bool LivesIn(string locale, IReadOnlyList<string> regions) => Region is { Length: > 0 } region
        && (string.Equals(RegionOf(locale), region, StringComparison.OrdinalIgnoreCase)
            || regions.Contains(region, StringComparer.OrdinalIgnoreCase));

    private static string LanguageOf(string locale) => locale.Split('-', '_')[0];

    private static string? RegionOf(string locale) => locale.Split('-', '_') is [_, var region, ..] ? region : null;

    #endregion
}
