using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// Balanced protection through the native app boundary: an encoded query
/// in, the encoded rule list out.
public sealed class AppSearchTests {
    [Fact]
    public void BalancedProtectionBlocksThirdPartyLoadsFromEveryListedHostAndItsSubdomains() {
        using var app = new AppClient();
        var list = app.Ask(new BalancedProtectionRules(), ContractCodec.ReadContentRuleList);
        Assert.Equal("com.pauldavis.crest.content-blocking.balanced.v2", list.Identifier);
        var rules = JsonNode.Parse(list.Source)!.AsArray();
        Assert.Equal(ContentBlockingPolicy.Balanced.BlockedHostSuffixes.Count, rules.Count);
        Assert.Null(ContentBlockingPolicy.Off.RuleList());
        var trigger = rules[0]!["trigger"]!;
        Assert.Equal(@"^[^:]+://+([^:/]+\.)?doubleclick\.net[:/]", trigger["url-filter"]!.GetValue<string>());
        Assert.Equal(["third-party"], trigger["load-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.DoesNotContain("document", trigger["resource-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.All(rules, rule => Assert.Equal("block", rule!["action"]!["type"]!.GetValue<string>()));
    }
}
