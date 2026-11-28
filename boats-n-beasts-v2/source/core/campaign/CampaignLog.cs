namespace BoatsNBeasts.Core;

public sealed record CampaignLog
{
    string[] voyages=[];
    HashSet<string> filed=[];
    public string[] Voyages
    {
        get=>voyages;
        init{voyages=value;filed=new(value,StringComparer.Ordinal);}
    }
    public bool Contains(string id)=>filed.Contains(id);
    public Dictionary<string,bool> FleetPacts { get; init; }=[];
    public Dictionary<string, bool> Decisions { get; init; } = [];
    public bool? CrewSigned { get; init; }
    public Dictionary<string,bool> NightWatches { get; init; } = [];
    public Shipmate OnWatch { get; init; }
    public bool? FreeMigration { get; init; }
    public bool StoryCleared => FreeMigration.HasValue;
    public bool NeedsCharter => !HomePortNamed && FarLedger.Arcs.Take(8).All(arc => FiledIn(arc)==arc.Length);
    public bool HomePortNamed => CrewSigned.HasValue;

    public int FiledIn(CampaignArc arc) => arc.Orders.Select((order,i) => arc.OrderAt(i,Decisions.GetValueOrDefault(arc.Region)))
        .Concat(arc.Islands.SelectMany(island=>island.Outings)).Count(order=>Contains(order.Id));

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
        && pos.Arc.Orders.Take(CampaignArc.Fork).All(order=>Contains(order.Id));
    public IEnumerable<CampaignOrder> Available()
    {
        if (Next is not { } pos || NeedsCharter) yield break;
        var arc = pos.Arc;
        bool second = Decisions.GetValueOrDefault(arc.Region);
        for(int i=0;i<=CampaignArc.Fork;i++)
        {
            var order=arc.OrderAt(i,second);
            if(Contains(order.Id))continue;
            if(i<CampaignArc.Fork || Decisions.ContainsKey(arc.Region))yield return order;
            yield break;
        }
        bool open = false;
        foreach (var island in arc.Islands)
        {
            var next = island.Outings.FirstOrDefault(order => !Contains(order.Id));
            if (next == null) continue;
            open = true;
            yield return next;
        }
        if (!open && arc.Orders.Skip(CampaignArc.Fork+1).FirstOrDefault(order=>!Contains(order.Id)) is { } backbone)
            yield return backbone;
    }
    public CampaignOrder? Current => Available().FirstOrDefault();
    public CampaignLog Sign(bool second)
    {
        if (!NeedsHearing || Next is not { } pos) return this;
        return this with { Decisions = new(Decisions) { [pos.Arc.Region] = second } };
    }
    public CampaignLog File(CampaignOrder order,bool? shoreBerth=null)
    {
        if(!Available().Any(o=>o.Id==order.Id))return this;
        var next=this with{Voyages=[..Voyages,order.Id]};
        return order.Flotilla && shoreBerth.HasValue
            ?next with{FleetPacts=new(FleetPacts){[order.Id]=shoreBerth.Value}}:next;
    }
    public string Homecoming(CampaignOrder order)
    {
        if(order.Articles is {} fleet && FleetPacts.TryGetValue(order.Id,out bool shore))
            return order.Homecoming+" "+(shore?fleet.Pledge:fleet.Berth);
        return order.Homecoming;
    }
    public bool Hosted(IslandStory island) => island.Outings.All(order => Contains(order.Id));
    public IEnumerable<CampaignArc> SettledPorts() => FarLedger.Arcs.Where(arc=>FiledIn(arc)==arc.Length);
}
