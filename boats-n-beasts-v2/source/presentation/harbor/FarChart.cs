using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    internal Action<CampaignOrder>? AcceptOrder;
    int logPage;

    void FarChart()
    {
        var log = Ledger.Campaign;
        if (log.NeedsHearing) { Listen(); return; }
        if (log.Current is { Island.Length: >0 }) { IslandRoutes(0); return; }
        if (log.Current is not { } order || log.Next is not { } route)
        {
            if (!log.HomePortNamed) { Ending(); return; }
            Open("THE SHIP’S LOG", "Back in familiar water", "The crew hangs the latest keepsake over the galley. Every ship in the bay has a different story about how it came here.");
        }
        else
        {
            string place = route.Stop == 0 ? route.Arc.Lead : order.Brief;
            Open($"{order.Region.ToUpperInvariant()}   /   {route.Arc.Title}", order.Title, place);
            Choice("Read the order", () => Brief(order), true);
        }
        chartMap = new RouteChart { Log = log, AnchorLeft = 1, AnchorRight = 1, OffsetLeft = -718,
            OffsetRight = -25, OffsetTop = 103, OffsetBottom = 370, MouseFilter = Godot.Control.MouseFilterEnum.Ignore };
        ui.AddChild(chartMap);
        if (log.Voyages.Length > 0) Choice("Leaf through the log", () => { logPage = log.Voyages.Length - 1; ShipLog(); });
        Choice("Crew recollections", Recollections);
        Choice("Leave the chart", Close);
    }

    void IslandRoutes(int page)
    {
        var log = Ledger.Campaign;
        var offers = log.Available().ToArray();
        var order = offers[page];
        var island = log.Next!.Value.Arc.Islands.First(i => i.Island == order.Island);
        string body = order.Id == island.Outings[0].Id ? island.Opening : order.Brief;
        Open($"{order.Region.ToUpperInvariant()}   /   {island.Speaker}", island.Island, body);
        chartMap = new RouteChart { Log=log, Coast=log.Next.Value.Arc, Selected=island.Island,
            Plot=name=>{int i=Array.FindIndex(offers,o=>o.Island==name); if(i>=0)IslandRoutes(i);},
            AnchorLeft=1,AnchorRight=1,OffsetLeft=-718,OffsetRight=-25,OffsetTop=103,OffsetBottom=383 };
        ui.AddChild(chartMap);
        Choice("Read the order", () => Brief(order), true);
        if (offers.Length > 1) Choice($"Another island   ·   {page+1}/{offers.Length}", () => IslandRoutes((page+1)%offers.Length));
        if (log.Voyages.Length > 0) Choice("Ship’s log", () => { logPage = log.Voyages.Length-1; ShipLog(); });
        Choice("Leave the chart",Close);
    }
    void Brief(CampaignOrder order)
    {
        Open(order.Pilotage ? "PILOT’S SURVEY" : order.Ashore ? "LANDING PARTY" : "BLUE-WATER VOYAGE",order.Title, order.Objective + "  " + order.Brief);
        Choice(order.Pilotage ? "Open the pilot book" : order.Ashore ? "Take the crew ashore" : "Cast off", () => AcceptOrder?.Invoke(order), true);
        Choice("Back to the chart", FarChart);
    }

    void Listen()
    {
        if (Ledger.Campaign.Next is not { } pos || !Ledger.Campaign.NeedsHearing) { FarChart(); return; }
        var hearing = pos.Arc.Hearing;
        Open(hearing.Speaker.ToUpperInvariant(), hearing.Question, hearing.Testimony);
        void Sign(bool second)
        {
            UpdateLedger(Ledger with { Campaign = Ledger.Campaign.Sign(second) });
            Open(pos.Arc.Region.ToUpperInvariant(), second ? hearing.Second : hearing.First, second ? hearing.SecondResult : hearing.FirstResult);
            Choice("Unroll the chart", FarChart, true);
        }
        Choice(hearing.First, () => Sign(false), true);
        Choice(hearing.Second, () => Sign(true));
        Choice("Think it over", Close);
    }
    void ShipLog()
    {
        var log = Ledger.Campaign;
        if (logPage < 0 || logPage >= log.Voyages.Length) { FarChart(); return; }
        var order = FarLedger.Find(log.Voyages[logPage]);
        Open($"SHIP’S LOG   /   {order.Region.ToUpperInvariant()}", order.Title,order.Homecoming);
        Choice("Relive this crossing", () => AcceptOrder?.Invoke(order));
        if (logPage > 0) Choice("Previous entry", () => { logPage--; ShipLog(); });
        if (logPage < log.Voyages.Length - 1) Choice("Next entry", () => { logPage++; ShipLog(); });
        Choice("Close the log", FarChart, true);
    }
    void Recollections()
    {
        Open("CREW RECOLLECTIONS", "The silent watch", "Lio reenacts the Keelwidow with a serving fork. Nell has brought much more flattering sketches of the Bellwarden. Choose the story you want the crew to tell again.");
        Choice("Lantern Sound", () => Depart?.Invoke(Passage.LanternSound), true);
        Choice("Bellwether Quay", () => Depart?.Invoke(Passage.BellwetherQuay));
        Choice("Return to the chart", FarChart);
    }
}
