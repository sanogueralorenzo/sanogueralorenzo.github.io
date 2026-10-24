using System.Globalization;
using System.Text;

using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// How a device keeps one built-in provider: on or off, the shortcuts the
/// person gave it or null for its own, and the values the person set for its
/// options.
public sealed record SearchProviderSettings(BuiltInSearchProvider Provider, bool IsEnabled, IReadOnlyList<string>? Shortcuts,
    IReadOnlyList<SearchOptionSetting> Options) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string>? Shortcuts {
        get;
        init => field = value is null ? null : [.. value];
    } = Shortcuts is null ? null : [.. Shortcuts];

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SearchOptionSetting> Options {
        get;
        init => field = [.. value];
    } = [.. Options];

    /// The shortcuts the provider answers to on this device.
    internal IReadOnlyList<string> Answers => Shortcuts ?? Provider.Shortcuts;

    /// The settings a device that never chose keeps for `provider`.
    internal static SearchProviderSettings Starting(BuiltInSearchProvider provider) => new(provider, provider.IsEnabledByDefault, null, []);

    #endregion

    #region Actions - Equality

    public bool Equals(SearchProviderSettings? other) => other is not null
        && Provider == other.Provider
        && IsEnabled == other.IsEnabled
        && (Shortcuts is null ? other.Shortcuts is null : other.Shortcuts is not null && Shortcuts.SequenceEqual(other.Shortcuts))
        && Options.SequenceEqual(other.Options);

    public override int GetHashCode() => HashCode.Combine(Provider, IsEnabled, Shortcuts?.Count, Options.Count);

    #endregion
}

/// The value a person set for `Option` of a built-in provider.
public sealed record SearchOptionSetting(SearchProviderOption Option, string Value);

#endregion

/// The search providers this device offers, which the device store keeps and
/// never syncs: every built-in, on or off with the person's shortcuts and
/// options, the providers the person added, the default search a Space
/// follows unless it chose its own and the one a private window's Space
/// follows, whether the default suggests searches, and the language and
/// region the platform reports, which automatic languages, regions and stores
/// follow.
public sealed record SearchCatalog(IReadOnlyList<SearchProviderSettings> BuiltIns, IReadOnlyList<CustomSearchProvider> Custom,
    BuiltInSearchProvider? DefaultBuiltIn, Guid? DefaultCustomId, BuiltInSearchProvider? PrivateBuiltIn, Guid? PrivateCustomId,
    bool SuggestionsEnabled, string? Language, string? Region) {
    #region Static Variables

    /// The most providers a person may add.
    public const int MaximumCustomCount = 32;

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SearchProviderSettings> BuiltIns {
        get;
        init => field = [.. value];
    } = [.. BuiltIns];

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<CustomSearchProvider> Custom {
        get;
        init => field = [.. value];
    } = [.. Custom];

    private SearchLocale Locale => new(Language, Region);

    /// Every provider as the device searches with it, the built-ins in their
    /// order and then the ones the person added.
    public IReadOnlyList<SearchProvider> Providers =>
        [.. BuiltIns.Select(settings => settings.Provider.Resolved(settings.Answers, settings.Options, Locale)),
            .. Custom.Select(custom => custom.Provider)];

    /// The providers the palette offers to Tab: the built-ins that are on and
    /// every provider the person added.
    public IEnumerable<SearchProvider> Enabled => Providers.Where(IsEnabled);

    /// The provider a Space that follows the default searches with: the one
    /// the person chose, else Google.
    public SearchProvider Default =>
        (DefaultCustomId is { } custom ? Custom.FirstOrDefault(provider => provider.Id == custom)?.Provider : null)
        ?? Resolving(DefaultBuiltIn ?? BuiltInSearchProvider.Google);

    /// The provider a private window's Space that follows the default
    /// searches with: the one the person chose for private windows, else
    /// DuckDuckGo.
    public SearchProvider PrivateDefault =>
        (PrivateCustomId is { } custom ? Custom.FirstOrDefault(provider => provider.Id == custom)?.Provider : null)
        ?? Resolving(PrivateBuiltIn ?? BuiltInSearchProvider.DuckDuckGo);

    #endregion

    #region Constructors

    /// What a device that never chose offers, in `language` and `region`:
    /// every built-in as it ships, Google as the default, DuckDuckGo in
    /// private windows, and no suggestions.
    internal static SearchCatalog Starting(string? language, string? region) =>
        new([.. BuiltInSearchProvider.All.Select(SearchProviderSettings.Starting)], [], BuiltInSearchProvider.Google, DefaultCustomId: null,
            BuiltInSearchProvider.DuckDuckGo, PrivateCustomId: null, SuggestionsEnabled: false, language, region);

    #endregion

    #region Actions - Reading

    /// Whether the palette offers `provider` to Tab.
    public bool IsEnabled(SearchProvider provider) =>
        provider.BuiltIn is { } builtIn ? Settings(builtIn).IsEnabled : Custom.Any(custom => custom.Id == provider.CustomId);

    /// How the device keeps `provider`.
    public SearchProviderSettings Settings(BuiltInSearchProvider provider) =>
        BuiltIns.FirstOrDefault(settings => settings.Provider == provider) ?? SearchProviderSettings.Starting(provider);

    /// `provider` as the device searches with it.
    public SearchProvider Resolving(BuiltInSearchProvider provider) {
        var settings = Settings(provider);
        return provider.Resolved(settings.Answers, settings.Options, Locale);
    }

    /// The provider whose name is `name`, on or off, or null for none.
    public SearchProvider? Named(string? name) => Providers.FirstOrDefault(provider => provider.Name == name);

    /// The default a Space follows: the private one in a private window.
    public SearchProvider DefaultFor(bool isPrivate) => isPrivate ? PrivateDefault : Default;

    /// What a Space with `browsing`, in a private window or not, searches
    /// with: the default while it follows it, else its own choice, as this
    /// device keeps a built-in or an added provider, or as the Space carries
    /// one this device lacks. A choice that names nothing searches with the
    /// default.
    public SearchProvider For(BrowsingPreferences browsing, bool isPrivate) {
        ArgumentNullException.ThrowIfNull(browsing);
        if (browsing.FollowsDefaultSearch) return DefaultFor(isPrivate);
        if (browsing.SelectedCustomEngineId is { } id)
            return Custom.FirstOrDefault(custom => custom.Id == id)?.Provider ?? Carried(browsing, id) ?? DefaultFor(isPrivate);
        return browsing.SelectedBuiltInEngine is { } builtIn ? Resolving(builtIn) : DefaultFor(isPrivate);
    }

    /// Whether a Space with `browsing` suggests searches as a person types.
    public bool SuggestsFor(BrowsingPreferences browsing) {
        ArgumentNullException.ThrowIfNull(browsing);
        return browsing.FollowsDefaultSuggestions ? SuggestionsEnabled : browsing.SearchSuggestionsEnabled;
    }

    /// The providers the palette offers that `word` names or starts to name,
    /// closest first, then in the catalog's order.
    public IReadOnlyList<SearchProvider> Matching(string word) {
        ArgumentNullException.ThrowIfNull(word);
        return [.. Enabled.Select((provider, order) => (provider, order, Closeness: provider.Closeness(word)))
            .Where(match => match.Closeness is not null).OrderBy(match => match.Closeness).ThenBy(match => match.order)
            .Select(match => match.provider)];
    }

    /// The provider the palette offers that `word` names exactly, the
    /// closest when several do, or null.
    internal SearchProvider? NamedBy(string word) => Matching(word).FirstOrDefault(provider => provider.IsNamedBy(word));

    /// The provider a Space carries with it, which this device does not keep,
    /// when it still validates.
    private static SearchProvider? Carried(BrowsingPreferences browsing, Guid id) {
        if (browsing.CustomSearchProviders.FirstOrDefault(custom => custom.Id == id) is not { } carried) return null;
        try {
            return carried.Admitted().Provider;
        } catch (Rejected) {
            return null;
        }
    }

    #endregion

    #region Actions - Restoring

    /// These settings as a device keeps them: every built-in once, in its
    /// order, each kept option one the provider has with a value it admits;
    /// the added providers that still validate, once each and at most
    /// `MaximumCustomCount`; and a default that is a provider the device
    /// keeps and may be one, else Google.
    public SearchCatalog Restored() {
        var builtIns = BuiltInSearchProvider.All.Select(provider => BuiltIns.FirstOrDefault(kept => kept.Provider == provider) is { } kept
            ? kept with {
                Options = [.. kept.Options.Where(setting => provider.Options.Contains(setting.Option) && setting.Option.Admits(setting.Value))
                    .DistinctBy(setting => setting.Option)]
            }
            : SearchProviderSettings.Starting(provider)).ToList();
        List<CustomSearchProvider> custom = [];
        foreach (var provider in Custom.DistinctBy(provider => provider.Id).Take(MaximumCustomCount)) {
            try {
                custom.Add(provider.Admitted());
            } catch (Rejected) {
                // One an older build stored that no longer validates is left out.
            }
        }
        var restored = this with { BuiltIns = builtIns, Custom = custom };
        if (!Kept(DefaultBuiltIn, DefaultCustomId, custom))
            restored = restored with { DefaultBuiltIn = BuiltInSearchProvider.Google, DefaultCustomId = null };
        if (!Kept(PrivateBuiltIn, PrivateCustomId, custom))
            restored = restored with { PrivateBuiltIn = BuiltInSearchProvider.DuckDuckGo, PrivateCustomId = null };
        return restored;
    }

    /// Whether `builtIn` or the added provider `id`, of `custom`, is one a
    /// default may be.
    private static bool Kept(BuiltInSearchProvider? builtIn, Guid? id, IReadOnlyList<CustomSearchProvider> custom) =>
        id is { } kept ? custom.Any(provider => provider.Id == kept && provider.Kind.CanBeDefault) : builtIn?.Kind.CanBeDefault ?? false;

    /// This catalog with the engines Spaces carried before the device kept
    /// providers of its own added as search engines, once each by identity
    /// and by address, up to the limit.
    internal SearchCatalog Adopting(IEnumerable<CustomSearchProvider> carried) {
        List<CustomSearchProvider> custom = [.. Custom];
        foreach (var engine in carried) {
            if (custom.Count >= MaximumCustomCount) break;
            if (custom.Any(kept => kept.Id == engine.Id || kept.SearchUrlTemplate == engine.SearchUrlTemplate)) continue;
            try {
                custom.Add((engine with { Kind = SearchProviderKind.Engine }).Admitted());
            } catch (Rejected) {
                // An engine that no longer validates stays with its Space.
            }
        }
        return this with { Custom = custom };
    }

    #endregion

    #region Mutators

    /// This catalog with `provider` as the default search. Throws `Rejected`
    /// with `UnknownSearchEngine` for a provider it does not keep and
    /// `UnsuitableDefaultSearch` for a website.
    public SearchCatalog Choosing(SearchProvider provider) {
        var known = Suitable(provider);
        return this with { DefaultBuiltIn = known.BuiltIn, DefaultCustomId = known.CustomId };
    }

    /// This catalog with `provider` as the default search in private windows.
    /// Throws `Rejected` as `Choosing` does.
    public SearchCatalog ChoosingPrivate(SearchProvider provider) {
        var known = Suitable(provider);
        return this with { PrivateBuiltIn = known.BuiltIn, PrivateCustomId = known.CustomId };
    }

    /// The provider `provider` names, which may be a default. Throws
    /// `Rejected` with `UnknownSearchEngine` or `UnsuitableDefaultSearch`.
    private SearchProvider Suitable(SearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        var known = Named(provider.Name) ?? throw new Rejected(new UnknownSearchEngine(provider.CustomId));
        return known.Kind.CanBeDefault ? known : throw new Rejected(new UnsuitableDefaultSearch());
    }

    /// This catalog with the default search suggesting searches or not.
    public SearchCatalog Suggesting(bool enabled) => this with { SuggestionsEnabled = enabled };

    /// This catalog with `provider` offered to Tab or not.
    public SearchCatalog Enabling(BuiltInSearchProvider provider, bool enabled) =>
        Revising(provider, settings => settings with { IsEnabled = enabled });

    /// This catalog with `provider` answering to `shortcuts`, or its own when
    /// null. Throws `Rejected` with `InvalidSearchShortcut` or
    /// `DuplicateSearchShortcut`.
    public SearchCatalog Naming(BuiltInSearchProvider provider, IReadOnlyList<string>? shortcuts) {
        ArgumentNullException.ThrowIfNull(provider);
        var admitted = shortcuts is null ? null : CustomSearchProvider.AdmittedShortcuts(shortcuts);
        var revised = Revising(provider, settings => settings with { Shortcuts = admitted is { Count: > 0 } ? admitted : null });
        revised.RequireDistinctShortcuts();
        return revised;
    }

    /// This catalog with `option` of `provider` set to `value`, or its default
    /// when `value` is blank. Throws `Rejected` with `UnknownSearchOption` for
    /// an option the provider lacks or a value the option refuses.
    public SearchCatalog Setting(BuiltInSearchProvider provider, SearchProviderOption option, string? value) {
        ArgumentNullException.ThrowIfNull(provider);
        ArgumentNullException.ThrowIfNull(option);
        string? kept = option.AcceptsText ? value?.Trim() : value;
        if (!provider.Options.Contains(option) || (!string.IsNullOrEmpty(kept) && !option.Admits(kept)))
            throw new Rejected(new UnknownSearchOption(option));
        return Revising(provider, settings => settings with {
            Options = [.. settings.Options.Where(setting => setting.Option != option),
                .. string.IsNullOrEmpty(kept) ? [] : new[] { new SearchOptionSetting(option, kept) }]
        });
    }

    /// This catalog with `provider` admitted in place of the added provider of
    /// its identity, or after the others. Throws `Rejected` naming the first
    /// rule it breaks: its own flaws, a name another added provider uses, a
    /// shortcut another provider answers to, or one provider too many.
    public SearchCatalog Saving(CustomSearchProvider provider) {
        ArgumentNullException.ThrowIfNull(provider);
        var admitted = provider.Admitted();
        var others = Custom.Where(kept => kept.Id != admitted.Id).ToList();
        if (others.Any(other => Fold(other.Name) == Fold(admitted.Name))) throw new Rejected(new DuplicateSearchEngineName());
        int index = Custom.ToList().FindIndex(kept => kept.Id == admitted.Id);
        if (index < 0 && Custom.Count >= MaximumCustomCount) throw new Rejected(new SearchEngineLimitReached(MaximumCustomCount));
        List<CustomSearchProvider> saved = [.. Custom];
        if (index < 0) saved.Add(admitted);
        else saved[index] = admitted;
        var revised = this with { Custom = saved };
        revised.RequireDistinctShortcuts();
        if (admitted.Kind.CanBeDefault) return revised;
        if (revised.DefaultCustomId == admitted.Id) revised = revised with { DefaultBuiltIn = BuiltInSearchProvider.Google, DefaultCustomId = null };
        if (revised.PrivateCustomId == admitted.Id)
            revised = revised with { PrivateBuiltIn = BuiltInSearchProvider.DuckDuckGo, PrivateCustomId = null };
        return revised;
    }

    /// This catalog without the added provider `id`; a default that was it
    /// becomes Google, and a private one DuckDuckGo.
    public SearchCatalog Removing(Guid id) {
        var revised = this with { Custom = [.. Custom.Where(provider => provider.Id != id)] };
        if (DefaultCustomId == id) revised = revised with { DefaultBuiltIn = BuiltInSearchProvider.Google, DefaultCustomId = null };
        if (PrivateCustomId == id) revised = revised with { PrivateBuiltIn = BuiltInSearchProvider.DuckDuckGo, PrivateCustomId = null };
        return revised;
    }

    /// This catalog with every built-in as it ships: on or off as it starts,
    /// with its own shortcuts and no options set. The providers the person
    /// added, the default and suggestions stay.
    public SearchCatalog Reset() => this with { BuiltIns = [.. BuiltInSearchProvider.All.Select(SearchProviderSettings.Starting)] };

    /// This catalog for a device in `language` and `region`.
    internal SearchCatalog Locating(string? language, string? region) => this with { Language = language, Region = region };

    /// This catalog with `revise` made to how it keeps `provider`.
    private SearchCatalog Revising(BuiltInSearchProvider provider, Func<SearchProviderSettings, SearchProviderSettings> revise) =>
        this with {
            BuiltIns = [.. BuiltInSearchProvider.All.Select(candidate => candidate == provider ? revise(Settings(candidate)) : Settings(candidate))]
        };

    /// Throws `Rejected` with `DuplicateSearchShortcut` when two providers,
    /// on or off, answer to one shortcut.
    private void RequireDistinctShortcuts() {
        var words = BuiltIns.SelectMany(settings => settings.Answers).Concat(Custom.SelectMany(provider => provider.Shortcuts)).ToList();
        if (words.Count != words.Distinct(StringComparer.Ordinal).Count()) throw new Rejected(new DuplicateSearchShortcut());
    }

    /// `value` for comparing names: trimmed, without diacritics, in capitals.
    private static string Fold(string value) => string.Concat(value.Trim().Normalize(NormalizationForm.FormD)
        .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)).ToUpperInvariant();

    #endregion

    #region Actions - Equality

    public bool Equals(SearchCatalog? other) => other is not null
        && BuiltIns.SequenceEqual(other.BuiltIns)
        && Custom.SequenceEqual(other.Custom)
        && DefaultBuiltIn == other.DefaultBuiltIn
        && DefaultCustomId == other.DefaultCustomId
        && PrivateBuiltIn == other.PrivateBuiltIn
        && PrivateCustomId == other.PrivateCustomId
        && SuggestionsEnabled == other.SuggestionsEnabled
        && Language == other.Language
        && Region == other.Region;

    public override int GetHashCode() =>
        HashCode.Combine(BuiltIns.Count, Custom.Count, DefaultBuiltIn, DefaultCustomId, PrivateBuiltIn, PrivateCustomId, SuggestionsEnabled,
            HashCode.Combine(Language, Region));

    #endregion
}
