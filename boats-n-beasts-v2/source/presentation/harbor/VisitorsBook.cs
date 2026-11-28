using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    (IslandStory Island,CampaignArc Arc)[] VisitingIslands()=>FarLedger.Arcs
        .SelectMany(arc=>arc.Islands.Where(Ledger.Campaign.Hosted).Select(island=>(island,arc))).ToArray();
    void WelcomeHome(CampaignOrder delivery)
    {
        var arc=FarLedger.Arcs[delivery.Tier-1];
        if(delivery.Island.Length>0)
        {
            var visitors=VisitingIslands();
            int page=Array.FindIndex(visitors,entry=>entry.Island.Outings[^1].Id==delivery.Id);
            if(page>=0)Choice("Unwrap the gift from "+delivery.Island,()=>VisitorsBook(page));
        }
        else if(arc.Orders[^1].Id==delivery.Id)
        {
            if(Ledger.Campaign.NeedsCharter || Ledger.Campaign.Next==null)
                Choice("Join the crew for the signing",Crew);
            if(CrewWatches.Thresholds.Contains(delivery.Tier))Choice("Stay for the night watch",NightWatch);
        }
    }
    void VisitorsBook(int page)
    {
        var visits = VisitingIslands();
        if (visits.Length == 0)
        {
            Open("NELL SPINDLE", "The visitors’ book", "Nell has sewn a pocket inside the cover for things that do not lie flat. “When an island has finished telling us its story, we ought to have somewhere to put what they send.”");
        }
        else
        {
            var (island,arc) = visits[page];
            Open($"THE VISITORS’ BOOK    /    {arc.Region.ToUpperInvariant()}    /    {page+1} OF {visits.Length}",
                island.Gift, $"{island.Speaker}   ·   {island.Island}\n{island.Outings[^1].Homecoming}");
            Choice("Read their first letter", () =>
            {
                Open(island.Speaker.ToUpperInvariant(),island.Island,island.Opening);
                Choice("Turn back the page", () => VisitorsBook(page),true);
            });
            if (visits.Length>1) Choice("Next keepsake", () => VisitorsBook((page+1)%visits.Length),true);
        }
        Choice("Leave the book with Nell", Close);
    }
}

public static partial class EnvironmentArt3D
{
    static void ReceivingPier(Sculptor art, CampaignLog log)
    {
        var colors = new Color[] {new("d16c42"),new("5c9b83"),new("bb8e46"),new("73a9bb"),
            new("9b78ae"),new("ce9476"),new("587b96"),new("ae626e"),new("c6a07c"),new("58b4a5"),new("e7a448"),new("8290bf"),new("85a4c4"),new("b67f50"),new("7a798a"),new("e9bd78")};
        var pine = new Color("976544");
        for (int region=0;region<FarLedger.Arcs.Count;region++)
        {
            var arc=FarLedger.Arcs[region];
            var wards=arc.Islands.Where(log.Hosted).ToArray();
            if (wards.Length==0) continue;
            float z=1.60f+region%8*.40f;
            var at=new Vector3(region<8?3.18f:1.10f,.15f,z);
            art.Tube(at-Vector3.Up*.4f,at+Vector3.Up*.88f,.065f,.053f,pine,8);
            for (int j=0;j<wards.Length;j++)
            {
                float h=.89f-j*.165f;
                var a=at+new Vector3(0,h,0);
                var b=a+new Vector3(0,-.137f,0);
                var c=a+new Vector3(.38f+.04f*(j%2),-.08f,.07f);
                art.Face(a,b,c,colors[region]);art.Face(c,b,a,colors[region]);
                art.Tube(a,c,.009f,.004f,new("f5d49b"),5);
            }
        }
        int built=0;
        foreach(var region in log.SettledPorts())
        {
            float x=-2.5f+built%4*.83f,z=3.72f+built/4*.64f;
            var at=new Vector3(x,.07f,z);
            for(int i=0;i<6;i++)
                art.RoundedBox(at+new Vector3(0,.12f,i*.10f),new(.85f,.13f,.093f),.016f,pine.Lightened(.035f*(i%3)));
            for(int side=-1;side<=1;side+=2)
                art.Tube(at+new Vector3(side*.35f,-.20f,.49f),at+new Vector3(side*.35f,.39f,.49f),.053f,.047f,pine,8);
            var box=at+new Vector3(.05f,.29f,.26f);
            art.RoundedBox(box,new(.34f,.26f,.28f),.033f,colors[built]);
            art.RoundedBox(box+Vector3.Up*.15f,new(.38f,.05f,.32f),.012f,new("d9b17d"));
            built++;
        }
    }
}
