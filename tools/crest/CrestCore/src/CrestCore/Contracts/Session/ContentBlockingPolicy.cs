using System.Text.Json.Nodes;

namespace CrestCore.Contracts;

/// How a Space blocks trackers and ads. Balanced is Crest's bundled protection:
/// third-party network loads from known advertising and analytics hosts, and
/// their subdomains, are blocked.
///
/// The stored session spells a policy as its `Name`, so a name never changes.
/// A policy travels as its index in `All`, so `All` is append-only.
public sealed class ContentBlockingPolicy {
    #region Variables

    /// Every resource a page fetches over the network; top-level documents are
    /// never blocked.
    private static readonly string[] NetworkResourceTypes = [
        "child-document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup", "ping", "fetch",
        "websocket", "csp-report", "other"
    ];

    public static readonly ContentBlockingPolicy Balanced = new(name: "balanced", title: "Balanced",
        switchTitle: "Turn Off Content Blocking in This Space", identifier: "com.pauldavis.crest.content-blocking.balanced.v2",
        blockedHostSuffixes: [
            "doubleclick.net",
            "googleadservices.com",
            "googlesyndication.com",
            "google-analytics.com",
            "googletagmanager.com",
            "ads-twitter.com",
            "analytics.twitter.com",
            "scorecardresearch.com",
            "quantserve.com",
            "hotjar.com",
            "segment.io",
            "segment.com",
            "mixpanel.com",
            "amplitude.com",
            "clarity.ms",
            "nr-data.net",
            "taboola.com",
            "outbrain.com",
            "snap.licdn.com"
        ]);
    public static readonly ContentBlockingPolicy Off = new(name: "off", title: "Off",
        switchTitle: "Turn On Balanced Content Blocking in This Space", identifier: null, blockedHostSuffixes: []);

    public static IReadOnlyList<ContentBlockingPolicy> All { get; } = [Balanced, Off];

    public string Name { get; }

    /// What the settings call the policy.
    [Localized]
    public string Title { get; }

    /// What a page's actions offer to switch the Space away from this policy.
    [Localized]
    public string SwitchTitle { get; }

    /// The versioned name a rule-list store compiles the policy's rules under,
    /// or null for a policy that blocks nothing. It changes with the rules.
    public string? Identifier { get; }

    /// The hosts whose third-party loads, and their subdomains', are blocked.
    public IReadOnlyList<string> BlockedHostSuffixes { get; }

    /// The policy blocks anything at all.
    public bool BlocksContent => BlockedHostSuffixes.Count > 0;

    #endregion

    #region Constructors

    private ContentBlockingPolicy(string name, string title, string switchTitle, string? identifier,
        IReadOnlyList<string> blockedHostSuffixes) {
        Name = name;
        Title = title;
        SwitchTitle = switchTitle;
        Identifier = identifier;
        BlockedHostSuffixes = blockedHostSuffixes;
    }

    #endregion

    #region Actions - Lookup

    public static ContentBlockingPolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion

    #region Actions - Rules

    /// The policy's rules as a content rule list, in the WebKit content-rule
    /// format, or null for a policy that blocks nothing. Each listed host and
    /// its subdomains are blocked for third-party network loads of every
    /// resource type but the top-level document.
    public ContentRuleList? RuleList() => Identifier is { } identifier ? new(identifier, RuleSource()) : null;

    private string RuleSource() => new JsonArray([.. BlockedHostSuffixes.Select(host => (JsonNode)new JsonObject {
        ["trigger"] = new JsonObject {
            ["url-filter"] = UrlFilter(host),
            ["url-filter-is-case-sensitive"] = true,
            ["load-type"] = new JsonArray("third-party"),
            ["resource-type"] = new JsonArray([.. NetworkResourceTypes.Select(type => (JsonNode?)JsonValue.Create(type))])
        },
        ["action"] = new JsonObject { ["type"] = "block" }
    })]).ToJsonString();

    /// The URL filter for one host suffix: any scheme, the host itself or any
    /// subdomain, followed by a port or path.
    private static string UrlFilter(string hostSuffix) =>
        $"^[^:]+://+([^:/]+\\.)?{hostSuffix.Replace(".", "\\.", StringComparison.Ordinal)}[:/]";

    #endregion
}
