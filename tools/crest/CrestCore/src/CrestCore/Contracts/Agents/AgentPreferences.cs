using System.Globalization;
using System.Text;

namespace CrestCore.Contracts;

#region Types

/// Who an agent is, as macOS verified the program that runs it: a signed
/// program by its team and signing identifier, any other by its path.
/// `Client` is the name the agent gave, which counts only for a general
/// interpreter such as node or python, since every agent it runs shares its
/// signature.
public sealed record AgentIdentity(string? TeamId, string? SigningId, string? Path, string? Client) {
    #region Static Variables

    public const int MaximumField = 255;
    public const int MaximumPath = 1024;

    #endregion

    #region Actions - Rules

    /// The identity with the name its agent gave cleaned as Crest shows names,
    /// which is how the device keeps and compares it.
    internal AgentIdentity Normalized() => this with { Client = AgentPreferences.CleanName(Client) };

    /// Whether the identity names a program: a team and signing identifier,
    /// or an absolute path, each within its bounds.
    internal bool IsValid {
        get {
            bool signed = !string.IsNullOrWhiteSpace(TeamId) && !string.IsNullOrWhiteSpace(SigningId) && Path is null
                && TeamId.Length <= MaximumField && SigningId.Length <= MaximumField;
            bool located = TeamId is null && SigningId is null && Path is { Length: > 1 and <= MaximumPath } path
                && path.StartsWith('/');
            return (signed || located) && Client is null or { Length: > 0 and <= AgentPreferences.MaximumName };
        }
    }

    #endregion
}

/// An agent the person allowed, and the name Crest shows it by.
public sealed record ApprovedAgent(AgentIdentity Identity, string Name);

#endregion

/// Whether agents, such as coding agents and scripts the person runs, may use
/// Crest on this Mac; whether they may run scripts in a page's own world; the
/// Spaces of the person's own session they may reach; and the agents the
/// person allowed. The device store keeps them and never syncs them. Each
/// edit answers the revised preferences, or throws the rule that refuses it.
public sealed record AgentPreferences(bool IsOn, bool RunsScripts, IReadOnlyList<Guid> SpaceIds,
    IReadOnlyList<ApprovedAgent> Agents) {
    #region Static Variables

    /// The preferences of a device that never chose any: off, reaching no
    /// Space and trusting no agent.
    internal static AgentPreferences Off { get; } = new(IsOn: false, RunsScripts: false, [], []);

    public const int MaximumAgents = 32;
    public const int MaximumName = 64;

    #endregion

    #region Actions - Spaces

    /// Allows or stops allowing agents to reach `spaceId`. An allowed Space
    /// keeps its place, and a newly allowed one goes after the others.
    public AgentPreferences Allowing(Guid spaceId, bool allowed) {
        var others = SpaceIds.Where(candidate => candidate != spaceId);
        if (!allowed) return this with { SpaceIds = [.. others] };
        return SpaceIds.Contains(spaceId) ? this : this with { SpaceIds = [.. others, spaceId] };
    }

    /// A deleted Space is no longer one agents may reach.
    public AgentPreferences Forgetting(Guid spaceId) => Allowing(spaceId, allowed: false);

    #endregion

    #region Actions - Agents

    /// Whether the person allowed the agent `identity` names.
    public bool Approves(AgentIdentity identity) {
        ArgumentNullException.ThrowIfNull(identity);
        var normalized = identity.Normalized();
        return Agents.Any(agent => agent.Identity == normalized);
    }

    /// Trusts `agent` from now on, under its cleaned name. An agent approved
    /// before keeps its place and takes the new name. Refused with
    /// `InvalidAgent` for an identity that names no program or a name with
    /// nothing to show, and with `AgentsFull` past `MaximumAgents`.
    public AgentPreferences Approving(ApprovedAgent agent) {
        ArgumentNullException.ThrowIfNull(agent);
        var identity = agent.Identity.Normalized();
        if (!identity.IsValid || CleanName(agent.Name) is not { } name) throw new Rejected(new InvalidAgent(MaximumName));
        var approved = new ApprovedAgent(identity, name);
        if (Agents.Any(candidate => candidate.Identity == identity))
            return this with { Agents = [.. Agents.Select(candidate => candidate.Identity == identity ? approved : candidate)] };
        if (Agents.Count >= MaximumAgents) throw new Rejected(new AgentsFull(MaximumAgents));
        return this with { Agents = [.. Agents, approved] };
    }

    /// Stops trusting the agent `identity` names; the next time it asks, the
    /// person is asked again.
    public AgentPreferences Forgetting(AgentIdentity identity) {
        ArgumentNullException.ThrowIfNull(identity);
        var normalized = identity.Normalized();
        return this with { Agents = [.. Agents.Where(candidate => candidate.Identity != normalized)] };
    }

    #endregion

    #region Actions - Names

    /// `name` as Crest shows it: without control or formatting characters,
    /// such as the ones that reverse text, with runs of space as one, and at
    /// most `MaximumName` characters, never cut inside a character or left
    /// ending in a space; null when nothing is left to show. Cleaning a
    /// cleaned name leaves it as it is, so a stored name finds itself again.
    public static string? CleanName(string? name) {
        if (name is null) return null;
        var cleaned = new StringBuilder();
        bool spaced = false;
        foreach (var rune in name.EnumerateRunes()) {
            var category = Rune.GetUnicodeCategory(rune);
            if (category is UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.LineSeparator
                or UnicodeCategory.ParagraphSeparator or UnicodeCategory.Surrogate or UnicodeCategory.PrivateUse
                or UnicodeCategory.OtherNotAssigned || Rune.IsWhiteSpace(rune)) {
                spaced = cleaned.Length > 0;
                continue;
            }
            // A space is kept only with the character after it, and neither
            // is kept past the limit.
            int length = (spaced ? 1 : 0) + rune.Utf16SequenceLength;
            if (cleaned.Length + length > MaximumName) break;
            if (spaced) cleaned.Append(' ');
            spaced = false;
            cleaned.Append(rune.ToString());
        }
        return cleaned.Length == 0 ? null : cleaned.ToString();
    }

    #endregion

    #region Actions - Equality

    public bool Equals(AgentPreferences? other) => other is not null && IsOn == other.IsOn && RunsScripts == other.RunsScripts
        && SpaceIds.SequenceEqual(other.SpaceIds) && Agents.SequenceEqual(other.Agents);

    public override int GetHashCode() => HashCode.Combine(IsOn, RunsScripts, SpaceIds.Count, Agents.Count);

    #endregion
}
