using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

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
        Assert.Equal(ContentBlockingPolicy.Balanced.Identifier, list.Identifier);
        var combinedRules = JsonNode.Parse(list.Source)!.AsArray();
        var rules = combinedRules.Where(rule => rule!["action"]!["type"]!.GetValue<string>() == "block").ToArray();
        Assert.Contains(combinedRules, rule => rule!["action"]!["type"]!.GetValue<string>() == "css-display-none");
        // A cosmetic exception must never bypass any of the network rules.
        var firstNetworkRule = combinedRules.IndexOf(rules[0]);
        Assert.All(combinedRules.Skip(firstNetworkRule), rule => Assert.Equal("block", rule!["action"]!["type"]!.GetValue<string>()));
        Assert.Equal(ContentBlockingPolicy.Balanced.BlockedHostSuffixes.Count, rules.Length);
        Assert.Null(ContentBlockingPolicy.Off.RuleList());
        var trigger = rules.Single(rule => Regex.IsMatch("https://ad.doubleclick.net/script.js",
            rule!["trigger"]!["url-filter"]!.GetValue<string>()))!["trigger"]!;
        Assert.Equal(@"^[^:]+://+([^:/]+\.)?doubleclick\.net[:/]", trigger["url-filter"]!.GetValue<string>());
        Assert.Equal(["third-party"], trigger["load-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.DoesNotContain("document", trigger["resource-type"]!.AsArray().Select(value => value!.GetValue<string>()));
        Assert.All(rules, rule => Assert.Equal("block", rule!["action"]!["type"]!.GetValue<string>()));
        foreach (var url in new[] { "https://ad.doubleclick.net/script.js", "https://insight.adsrvr.org/track", "https://ib.adnxs.com/ad", "https://fundingchoicesmessages.google.com/i/pub-123", "https://sub.fundingchoicesmessages.google.com/f/script.js" })
            Assert.Contains(rules, rule => Regex.IsMatch(url, rule!["trigger"]!["url-filter"]!.GetValue<string>()));
        foreach (var url in new[] { "https://notdoubleclick.net/ad", "https://doubleclick.net.example.org/ad", "https://www.github.com/", "https://www.20minutos.es/", "https://notfundingchoicesmessages.google.com/", "https://fundingchoicesmessages.google.com.example.org/" })
            Assert.DoesNotContain(rules, rule => Regex.IsMatch(url, rule!["trigger"]!["url-filter"]!.GetValue<string>()));
    }
}
