namespace CrestCore.Contracts;

/// Who owns a navigation once its URL scheme is known. A disposition travels
/// as its index in `All`, so `All` is append-only.
public sealed class ExternalSchemeDisposition {
    #region Types

    /// Each platform routes a navigation with its own code, so the one place
    /// that routes it switches over the kind.
    public enum Kinds { Engine, Blocked, HandOff }

    #endregion

    #region Variables

    /// The page engine's to load, or to refuse on its own terms.
    public static readonly ExternalSchemeDisposition Engine = new(Kinds.Engine, name: "engine");
    /// Neither the engine nor another application may see it.
    public static readonly ExternalSchemeDisposition Blocked = new(Kinds.Blocked, name: "blocked");
    /// Another application owns the scheme; Crest hands it to the system after consent.
    public static readonly ExternalSchemeDisposition HandOff = new(Kinds.HandOff, name: "handOff");

    public static IReadOnlyList<ExternalSchemeDisposition> All { get; } = [Engine, Blocked, HandOff];

    public Kinds Kind { get; }
    public string Name { get; }

    #endregion

    #region Constructors

    private ExternalSchemeDisposition(Kinds kind, string name) {
        Kind = kind;
        Name = name;
    }

    #endregion

    #region Actions - Lookup

    public static ExternalSchemeDisposition? Named(string? name) => All.FirstOrDefault(disposition => disposition.Name == name);

    #endregion
}
