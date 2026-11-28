namespace BoatsNBeasts.Core;

public sealed record IslandStory(string Island, string Speaker, string Opening, string Gift,
    CampaignOrder[] Outings);

public static partial class FarLedger
{
    static IslandStory Isle(string region, int tier, string island, string speaker, string opening, string gift,
        params CampaignOrder[] sailings)
    {
        var chart = new CampaignOrder(sailings[0].Id+"-approach",region,"The approach to "+island,
            speaker+" has the first sight written down. The coast pilots can supply a second bearing from the lights.",
            "Plot the crossing of each pair of bearings, cast the lead there, and deliver the depths to the island tender.",
            "", "The pilots of "+island+" copy the soundings onto their own chart. The landing is open.",
            SeaDuty.Sounding,tier,3+Math.Min(2,tier/3)){ Island=island, Pilotage=true };
        return new(island,speaker,opening,gift,
            [chart,..sailings.Select(o=>o with { Region=region, Tier=tier, Island=island })]);
    }
}
