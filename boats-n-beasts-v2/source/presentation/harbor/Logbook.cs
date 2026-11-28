using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    void LogRegions(int book)
    {
        var log=Ledger.Campaign;
        Open("THE SHIP’S LOG",book==0?"The Far Ledger":"The Walking Tide",
            "Choose a region to find its island stories, hearing and completed orders.");
        foreach(var arc in FarLedger.Arcs.Skip(book*8).Take(8))
        {
            int filed=log.FiledIn(arc);
            if(filed>0)Choice($"{arc.Region}  ·  {filed}/{arc.Length}",()=>LogRegion(arc));
        }
        if(log.HomePortNamed)Choice(book==0?"Outer regions":"Inner regions",()=>LogRegions(1-book));
        Choice("Close the log",FarChart);
    }
    void LogRegion(CampaignArc arc)
    {
        var log=Ledger.Campaign;
        string story=log.Decisions.TryGetValue(arc.Region,out bool second)?second?arc.Hearing.SecondResult:arc.Hearing.FirstResult:arc.Lead;
        Open($"{arc.Region.ToUpperInvariant()}    /    {log.FiledIn(arc)} OF {arc.Length} FILED",arc.Title,story);
        Choice("Regional orders",()=>IslandLog(arc,"",0),true);
        foreach(var island in arc.Islands.Where(i=>i.Outings.Any(o=>log.Contains(o.Id))))
            Choice(island.Island,()=>IslandLog(arc,island.Island,0));
        Choice("Other regions",()=>LogRegions(arc.Orders[0].Tier>8?1:0));
    }
    void IslandLog(CampaignArc arc,string name,int page)
    {
        var log=Ledger.Campaign;
        var entries=log.Voyages.Select(FarLedger.Find).Where(o=>o.Region==arc.Region && o.Island==name).ToArray();
        if(entries.Length==0){LogRegion(arc);return;}
        var order=entries[Math.Clamp(page,0,entries.Length-1)];
        Open($"{arc.Region.ToUpperInvariant()}   /   {(name.Length>0?name:"REGIONAL ORDERS")}   /   {page+1} OF {entries.Length}",order.Title,log.Homecoming(order));
        Choice("Sail this recollection",()=>AcceptOrder?.Invoke(order),true);
        if(page>0)Choice("Previous",()=>IslandLog(arc,name,page-1));
        if(page<entries.Length-1)Choice("Next",()=>IslandLog(arc,name,page+1));
        Choice("Other entries",()=>LogRegion(arc));
    }
}
