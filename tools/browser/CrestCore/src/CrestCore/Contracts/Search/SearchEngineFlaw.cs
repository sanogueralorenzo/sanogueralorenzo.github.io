namespace CrestCore.Contracts;

/// What makes a custom search engine unusable, with the explanation the
/// engine editor shows. A flaw travels as its index in `All`, so `All` is
/// append-only.
public sealed class SearchEngineFlaw {
    #region Variables

    public static readonly SearchEngineFlaw InvalidIdentity = new(name: "invalidIdentity", message: "Enter a valid URL template.");
    public static readonly SearchEngineFlaw EmptyName = new(name: "emptyName", message: "Enter a name for this search engine.");
    public static readonly SearchEngineFlaw NameTooLong = new(name: "nameTooLong",
        message: "Search engine names must be 64 characters or fewer.");
    public static readonly SearchEngineFlaw TemplateTooLong = new(name: "templateTooLong",
        message: "URL templates must be 2,048 characters or fewer.");
    public static readonly SearchEngineFlaw MissingPlaceholder = new(name: "missingPlaceholder",
        message: "Include exactly one %s or {searchTerms} query placeholder.");
    public static readonly SearchEngineFlaw AmbiguousPlaceholder = new(name: "ambiguousPlaceholder",
        message: "Use exactly one query placeholder.");
    public static readonly SearchEngineFlaw InvalidTemplate = new(name: "invalidTemplate", message: "Enter a valid URL template.");
    public static readonly SearchEngineFlaw RequiresHttps = new(name: "requiresHttps", message: "Search engine templates must use HTTPS.");
    public static readonly SearchEngineFlaw UnsafeHost = new(name: "unsafeHost",
        message: "Use a public search engine host, not a local or numeric address.");
    public static readonly SearchEngineFlaw NonstandardPort = new(name: "nonstandardPort",
        message: "Search engine templates may only use the standard HTTPS port.");
    public static readonly SearchEngineFlaw CredentialsInTemplate = new(name: "credentialsInTemplate",
        message: "Usernames and passwords cannot be stored in a search template.");
    public static readonly SearchEngineFlaw PlaceholderInFragment = new(name: "placeholderInFragment",
        message: "Put the query placeholder in the path or query, not the fragment.");
    public static readonly SearchEngineFlaw SecretInTemplate = new(name: "secretInTemplate",
        message: "Authentication tokens and other secrets cannot be stored in a search template. Sign in on the search engine website instead.");

    public static IReadOnlyList<SearchEngineFlaw> All { get; } = [InvalidIdentity, EmptyName, NameTooLong, TemplateTooLong,
        MissingPlaceholder, AmbiguousPlaceholder, InvalidTemplate, RequiresHttps, UnsafeHost, NonstandardPort, CredentialsInTemplate,
        PlaceholderInFragment, SecretInTemplate];

    public string Name { get; }

    /// What the engine editor tells the person.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private SearchEngineFlaw(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static SearchEngineFlaw? Named(string? name) => All.FirstOrDefault(flaw => flaw.Name == name);

    #endregion
}
