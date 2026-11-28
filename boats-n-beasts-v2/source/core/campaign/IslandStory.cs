namespace BoatsNBeasts.Core;

public sealed record IslandStory(string Island, string Speaker, string Opening, string Gift,
    CampaignOrder[] Outings)
{
    public PostLetter? Mail { get; init; }
}

public static partial class FarLedger
{
    static IslandStory Isle(string region,int tier,string island,string speaker,string opening,string gift,
        PostLetter letter,params CampaignOrder[] sailings) =>
        Isle(region,tier,island,speaker,opening,gift,sailings) with { Mail=letter };
    static IslandStory Isle(string region, int tier, string island, string speaker, string opening, string gift,
        params CampaignOrder[] sailings)
    {
        var chart = new CampaignOrder(sailings[0].Id+"-approach",region,"The approach to "+island,
            speaker+" has the first sight written down. The coast pilots can supply a second bearing from the lights.",
            "Plot the crossing of each pair of bearings, cast the lead there, and deliver the depths to the island tender.",
            "", "The pilots of "+island+" copy the soundings onto their own chart. The landing is open.",
            SeaDuty.Sounding,tier,3+Math.Min(2,tier/3)){ Island=island, Pilotage=true };
        if(tier>8)chart=chart with
        {
            Title="The young reefs of "+island,
            Brief=speaker+" reports that calves have strayed into the shipping lanes. The nursery mother is holding open water for them.",
            Objective="Answer the calves’ calls, bring them safely into the mother’s lee, and hail the nursery tender.",
            Homecoming="A green frond waves from each small reef as the mother takes them into the lee of "+island+". The islanders put out the landing lamps.",
            Pilotage=false,Migration=true
        };
        return new(island,speaker,opening,gift,
            [chart,..sailings.Select((o,index)=>o with { Region=region, Tier=tier, Island=island, Postal=index==2 })]);
    }
}
