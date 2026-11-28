namespace BoatsNBeasts.Core;

public sealed record CampaignLog
{
    public string[] Voyages { get; init; } = [];
    public Dictionary<string, bool> Decisions { get; init; } = [];
    public bool? CrewSigned { get; init; }
    public bool HomePortNamed => CrewSigned.HasValue;
    public (CampaignArc Arc,int Stop)? Next => FarLedger.Locate(Voyages.Length);
    public bool NeedsHearing => Next is { } pos && pos.Stop == CampaignArc.Fork && !Decisions.ContainsKey(pos.Arc.Region);
    public IEnumerable<CampaignOrder> Available()
    {
        if (Next is not { } pos || NeedsHearing) yield break;
        var arc = pos.Arc;
        bool second = Decisions.GetValueOrDefault(arc.Region);
        if (pos.Stop <= CampaignArc.Fork)
        {
            yield return arc.OrderAt(pos.Stop,second);
            yield break;
        }
        bool open = false;
        foreach (var island in arc.Islands)
        {
            var next = island.Outings.FirstOrDefault(order => !Voyages.Contains(order.Id));
            if (next == null) continue;
            open = true;
            yield return next;
        }
        if (!open)
        {
            int backbone = pos.Stop - (arc.Length-arc.Orders.Length);
            yield return arc.OrderAt(backbone,second);
        }
    }
    public CampaignOrder? Current => Available().FirstOrDefault();
    public CampaignLog Sign(bool second)
    {
        if (!NeedsHearing || Next is not { } pos) return this;
        return this with { Decisions = new(Decisions) { [pos.Arc.Region] = second } };
    }
    public CampaignLog File(CampaignOrder order) =>
        Available().Any(o => o.Id == order.Id) ? this with { Voyages = [..Voyages, order.Id] } : this;
    public IEnumerable<CampaignArc> SettledPorts()
    {
        int end = 0;
        foreach (var arc in FarLedger.Arcs)
        {
            end += arc.Length;
            if (end > Voyages.Length) yield break;
            yield return arc;
        }
    }
}
