namespace CrestCore.Domain;

/// One change an option makes to its provider's search address, which the
/// edit applies itself: a query parameter it sets, or a slot it fills.
internal abstract record SearchEdit {
    #region Variables

    /// Whether the provider's suggestions address takes the edit too, as it
    /// does a language but not a filter on results.
    internal abstract bool ReachesSuggestions { get; }

    #endregion

    #region Abstract Methods

    /// `template` with this edit made.
    internal abstract SearchTemplate Applied(SearchTemplate template);

    #endregion
}

/// Sets the query parameter `Name` to `Value`, replacing the address's own
/// value for it. `Value` is spelled as the address carries it, already
/// percent-encoded. It filters or shapes results, so suggestions never take it.
internal sealed record AddsParameter(string Name, string Value) : SearchEdit {
    #region Variables

    internal override bool ReachesSuggestions => false;

    #endregion

    #region Actions - Editing

    internal override SearchTemplate Applied(SearchTemplate template) => template.Setting(Name, Value);

    #endregion
}

/// Fills `Slot` with `Value`. A slot names where the provider answers, so its
/// suggestions take it too.
internal sealed record FillsSlot(SearchSlot Slot, string Value) : SearchEdit {
    #region Variables

    internal override bool ReachesSuggestions => true;

    #endregion

    #region Actions - Editing

    internal override SearchTemplate Applied(SearchTemplate template) => template.Filling(Slot, Value);

    #endregion
}
