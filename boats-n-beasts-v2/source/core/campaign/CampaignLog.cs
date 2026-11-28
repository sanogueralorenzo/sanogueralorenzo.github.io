namespace BoatsNBeasts.Core;

public sealed record CampaignLog
{
    public string[] Voyages { get; init; } = [];
    public Dictionary<string, bool> Decisions { get; init; } = [];
    public bool? CrewSigned { get; init; }
    public bool HomePortNamed => CrewSigned.HasValue;

    int FiledIn(CampaignArc arc) => arc.Orders.Select((order,i) => arc.OrderAt(i,Decisions.GetValueOrDefault(arc.Region)))
        .Concat(arc.Islands.SelectMany(island=>island.Outings)).Count(order=>Voyages.Contains(order.Id));

    public (CampaignArc Arc,int Stop)? Next
    {
        get
        {
            foreach(var arc in FarLedger.Arcs)
            {
                int filed=FiledIn(arc);
                if(filed<arc.Length)return (arc,filed);
            }
            return null;
        }
    }
    public bool NeedsHearing => Next is { } pos && !Decisions.ContainsKey(pos.Arc.Region)
        && pos.Arc.Orders.Take(CampaignArc.Fork).All(order=>Voyages.Contains(order.Id));
    public IEnumerable<CampaignOrder> Available()
    {
        if (Next is not { } pos) yield break;
        var arc = pos.Arc;
        bool second = Decisions.GetValueOrDefault(arc.Region);
        for(int i=0;i<=CampaignArc.Fork;i++)
        {
            var order=arc.OrderAt(i,second);
            if(Voyages.Contains(order.Id))continue;
            if(i<CampaignArc.Fork || Decisions.ContainsKey(arc.Region))yield return order;
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
        if (!open && arc.Orders.Skip(CampaignArc.Fork+1).FirstOrDefault(order=>!Voyages.Contains(order.Id)) is { } backbone)
            yield return backbone;
    }
    public CampaignOrder? Current => Available().FirstOrDefault();
    public CampaignLog Sign(bool second)
    {
        if (!NeedsHearing || Next is not { } pos) return this;
        return this with { Decisions = new(Decisions) { [pos.Arc.Region] = second } };
    }
    public CampaignLog File(CampaignOrder order) =>
        Available().Any(o => o.Id == order.Id) ? this with { Voyages = [..Voyages, order.Id] } : this;
    public bool Hosted(IslandStory island) => island.Outings.All(order => Voyages.Contains(order.Id));
    public IEnumerable<CampaignArc> SettledPorts() => FarLedger.Arcs.Where(arc=>FiledIn(arc)==arc.Length);
}
