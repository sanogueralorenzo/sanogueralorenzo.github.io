using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace CrestCore.Contracts;

/// How a Space blocks trackers and ads. Balanced is Crest's bundled protection:
/// third-party network loads from known advertising and analytics hosts, and
/// their subdomains, are blocked. EasyList cosmetic rules collapse ad containers.
///
/// The stored session spells a policy as its `Name`, so a name never changes.
/// A policy travels as its index in `All`, so `All` is append-only.
public sealed class ContentBlockingPolicy {
    #region Static Variables

    /// Every resource a page fetches over the network; top-level documents are
    /// never blocked.
    private static readonly string[] NetworkResourceTypes = [
        "child-document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup", "ping", "fetch",
        "websocket", "csp-report", "other"
    ];

    private static readonly string[] BalancedHosts = ReadBundledHosts();
    public static readonly ContentBlockingPolicy Balanced = new(name: "balanced", title: "Balanced",
        switchTitle: "Turn Off Content Blocking in This Space",
        blockedHostSuffixes: BalancedHosts,
        cosmeticRules: ReadBundledResource("CrestCore.ContentBlockingCosmetics"));
    public static readonly ContentBlockingPolicy Off = new(name: "off", title: "Off",
        switchTitle: "Turn On Balanced Content Blocking in This Space", blockedHostSuffixes: [], cosmeticRules: null);

    public static IReadOnlyList<ContentBlockingPolicy> All { get; } = [Balanced, Off];

    #endregion

    #region Variables

    private readonly string? ruleSource;

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
    internal IReadOnlyList<string> BlockedHostSuffixes { get; }

    /// The policy blocks anything at all.
    public bool BlocksContent => ruleSource is not null;

    #endregion

    #region Constructors

    private ContentBlockingPolicy(string name, string title, string switchTitle,
        IReadOnlyList<string> blockedHostSuffixes, string? cosmeticRules) {
        Name = name;
        Title = title;
        SwitchTitle = switchTitle;
        BlockedHostSuffixes = blockedHostSuffixes;
        if (blockedHostSuffixes.Count > 0 || cosmeticRules is not null) {
            ruleSource = RuleSource(blockedHostSuffixes, cosmeticRules);
            Identifier = $"com.pauldavis.crest.content-blocking.balanced.v4.{Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(ruleSource)))}";
        }
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
    public ContentRuleList? RuleList() => Identifier is { } identifier && ruleSource is { } source ? new(identifier, source) : null;

    private static string ReadBundledResource(string name) {
        using var stream = typeof(ContentBlockingPolicy).Assembly.GetManifestResourceStream(name)
            ?? throw new InvalidOperationException($"The bundled content-blocking resource {name} is missing.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static string[] ReadBundledHosts() => [.. ReadBundledResource("CrestCore.ContentBlockingHosts").Split('\n')
        .Where(line => !string.IsNullOrWhiteSpace(line) && !line.StartsWith('#'))
        .Select(line => line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)[1])
        .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)];

    private static string RuleSource(IReadOnlyList<string> hosts, string? cosmeticRules) {
        var rules = cosmeticRules is null ? new JsonArray() : JsonNode.Parse(cosmeticRules)!.AsArray();
        // Cosmetic exceptions precede network rules so they cannot disable host protection.
        foreach (var host in hosts) {
            rules.Add((JsonNode)new JsonObject {
                ["trigger"] = new JsonObject {
                    ["url-filter"] = UrlFilter(host),
                    ["url-filter-is-case-sensitive"] = true,
                    ["load-type"] = new JsonArray("third-party"),
                    ["resource-type"] = new JsonArray([.. NetworkResourceTypes.Select(type => (JsonNode?)JsonValue.Create(type))])
                },
                ["action"] = new JsonObject { ["type"] = "block" }
            });
        }
        return rules.ToJsonString();
    }

    /// The URL filter for one host suffix: any scheme, the host itself or any
    /// subdomain, followed by a port or path.
    private static string UrlFilter(string hostSuffix) =>
        $"^[^:]+://+([^:/]+\\.)?{hostSuffix.Replace(".", "\\.", StringComparison.Ordinal)}[:/]";

    #endregion
}
