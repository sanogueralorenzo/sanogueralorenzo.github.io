import Foundation

/// The edits the Search settings make to the palette preferences, each a
/// whole new record the core then keeps.
extension PalettePreferences {
    /// The kinds that show under their own header, in the person's order.
    /// Search suggestions always come last, and the search engine settings
    /// turn them on or off, so they are not among them.
    var sections: [PaletteSourceChoice] { sources.filter { $0.source.isSection && $0.source != .suggestions } }

    /// The kinds that join a section or lead the list, in catalog order.
    var extras: [PaletteSourceChoice] { sources.filter { !$0.source.isSection } }

    /// The numbers of rows a section may be set to show.
    static let limits = Array(1...10) + [15, 20]

    /// These preferences with `source` offered or not.
    func offering(_ source: PaletteSource, _ isEnabled: Bool) -> PalettePreferences {
        editing(source) { $0.isEnabled = isEnabled }
    }

    /// The most rows `source` shows: the person's number, else the kind's own.
    func limit(of source: PaletteSource) -> Int {
        sources.first { $0.source == source }?.limit ?? source.defaultLimit
    }

    /// These preferences with `source` showing at most `limit` rows, or its
    /// own number when `limit` is that number.
    func limiting(_ source: PaletteSource, to limit: Int) -> PalettePreferences {
        editing(source) { $0.limit = limit == source.defaultLimit ? nil : limit }
    }

    private func editing(_ source: PaletteSource, _ edit: (inout PaletteSourceChoice) -> Void) -> PalettePreferences {
        var edited = self
        edited.sources = sources.map { choice in
            guard choice.source == source else { return choice }
            var changed = choice
            edit(&changed)
            return changed
        }
        return edited
    }

    /// These preferences with the sections at `offsets` moved before `destination`,
    /// both counted among the sections alone.
    func movingSections(from offsets: IndexSet, to destination: Int) -> PalettePreferences {
        var ordered = sections
        ordered.move(fromOffsets: offsets, toOffset: destination)
        var edited = self
        edited.sources = ordered + sources.filter { !ordered.map(\.source).contains($0.source) }
        return edited
    }

    /// These preferences with the section `source` moved to where `target`
    /// stands among the sections, as a drag over `target` moves it.
    func moving(_ source: PaletteSource, to target: PaletteSource) -> PalettePreferences {
        let order = sections.map(\.source)
        guard let from = order.firstIndex(of: source), let to = order.firstIndex(of: target), from != to else {
            return self
        }
        return movingSections(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
    }

    /// These preferences with the sections in their default order, each kept
    /// on or off as the person set it.
    func restoringSectionOrder() -> PalettePreferences {
        var edited = self
        let ordered = PalettePreferences.default.sections.map { choice in
            sources.first { $0.source == choice.source } ?? choice
        }
        edited.sources = ordered + sources.filter { !ordered.map(\.source).contains($0.source) }
        return edited
    }
}
