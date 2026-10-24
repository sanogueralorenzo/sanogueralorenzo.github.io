namespace CrestCore.Contracts;

/// The palette's rows, in the groups it shows them, first to last. The first
/// row is what Return activates: the best match when one clearly leads, else
/// the address or search for the text. `Completion` completes the text as an
/// address the Space already knows, or is null. `SuggestionAddress` is where
/// the platform may fetch search suggestions for the text, or null when the
/// window is private, the Space does not offer them, the person narrowed the
/// palette, or the provider has none. `OfferedSearch` is the search provider
/// Tab would enter for the text, and `OfferedScope` the scope; each is null
/// when Tab offers none. `MatchingProviders` are every provider the text
/// names or starts to name while it is one word, closest first, which the
/// palette offers as chips. `Entry` is the provider or scope the text names
/// in the palette's notation, which the platform enters at once, or null.
public sealed record PaletteAnswer(IReadOnlyList<PaletteGroup> Groups, AddressCompletion? Completion, string? SuggestionAddress,
    SearchOffer? OfferedSearch, PaletteScope? OfferedScope, IReadOnlyList<SearchProvider> MatchingProviders, PaletteEntry? Entry) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SearchProvider> MatchingProviders {
        get;
        init => field = [.. value];
    } = [.. MatchingProviders];

    #endregion
}

/// What a person typed in the palette's notation: `$` and a search
/// provider's shortcut or name, or a scope's `@` keyword, then a space. The
/// platform enters `Provider` or `Scope`, whichever is set, without waiting
/// for Tab, and keeps `Text`, what followed the space, as what is typed.
public sealed record PaletteEntry(SearchProvider? Provider, PaletteScope? Scope, string Text);

/// The search provider Tab enters for what a person typed: the closest that
/// the text names or starts to name. Tab takes the offer over accepting a
/// completion when the text is exactly one of the provider's shortcuts,
/// `BeatsCompletion`; any other waits until no completion shows.
public sealed record SearchOffer(SearchProvider Provider, bool BeatsCompletion);

/// Completes what a person typed, `Typed`, as an address the Space already
/// knows: `Suffix` follows the text as typed, and accepting the completion
/// leaves `Accepted`, the address it opens, which may name a scheme or a
/// `www.` the person did not type.
public sealed record AddressCompletion(string Typed, string Suffix, string Accepted);

/// Rows of one section of the palette, in the order it ranked them.
public sealed record PaletteGroup(PaletteSection Section, IReadOnlyList<PaletteRow> Rows);

/// One thing the palette offers. Activating it shows `TabId`, opens `Address`,
/// performs `Command`, enters the search provider `Provider`, opens the settings page
/// `SettingsPage` or narrows to `Scope`, whichever it names. `SubjectId` is
/// what the row stands for when that is not its target: the folder a folder
/// row opens the first tab of, a history entry, a Space to switch to or an
/// archived tab to reopen. A search row names the provider it searches with
/// in `Provider`. `Symbol` is the SF Symbol the row wears when no tab icon or
/// provider icon stands for it. `Reason` says why the row ranked where it did.
public sealed record PaletteRow(PaletteRowKind Kind, string Title, string Subtitle, string Symbol, Guid? SubjectId, Guid? TabId,
    string? Address, ShortcutCommand? Command, SearchProvider? Provider, string? SettingsPage, PaletteScope? Scope, PaletteReason? Reason) {
    #region Constructors

    /// A row of `kind` with only what it names, wearing its kind's symbol
    /// unless it names its own.
    internal static PaletteRow Of(PaletteRowKind kind, string title, string subtitle, string? symbol = null, Guid? subject = null,
        Guid? tab = null, string? address = null, ShortcutCommand? command = null, SearchProvider? provider = null, string? page = null,
        PaletteScope? scope = null, PaletteReason? reason = null) =>
        new(kind, title, subtitle, symbol ?? kind.Symbol, subject, tab, address, command, provider, page, scope, reason);

    #endregion
}

/// A command the palette may offer, with the title and section title the
/// platform shows for it, which ranking matches what a person types against.
public sealed record PaletteCommand(ShortcutCommand Command, string Title, string SectionTitle);

/// A settings page the palette may open, named as the platform's settings name
/// it, with its title and the words a person might type to find it.
public sealed record PaletteSettingsPage(string Name, string Title, string Terms);
