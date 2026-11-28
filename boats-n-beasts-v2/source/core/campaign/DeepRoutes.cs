namespace BoatsNBeasts.Core;

internal sealed record DeepWrit(string Title,string Brief,string Objective,string Captain,string Landfall);

internal static partial class DeepRoutes
{
    internal static CampaignArc Open(CampaignArc arc,IslandStory[] isles)
    {
        int tier=arc.Orders[0].Tier;
        var book=tier<=8?Inner[tier-1]:Outer[tier-9];
        CampaignOrder Build(int slot,string id,string island)
        {
            var writ=book[slot];bool underground=slot==4 ? tier%2==0 : slot%2!=0;
            return new(id+(underground?"-underways":"-prize"),arc.Region,writ.Title,writ.Brief,writ.Objective,writ.Captain,writ.Landfall,
                underground?SeaDuty.Landing:SeaDuty.Hunt,tier,slot==4?7:5)
                { Island=island,Underways=underground,PrizeWatch=!underground,Evidence=Evidence[tier-1][slot] };
        }
        var extended=isles.Select((story,i)=>
        {
            var special=Build(i,story.Outings[0].Id,story.Island);
            return story with{ Outings=[..story.Outings[..^1],special,story.Outings[^1]] };
        }).ToArray();
        return arc with {Islands=extended,Orders=[..arc.Orders[..^1],Build(4,arc.Orders[^1].Id,""),arc.Orders[^1]]};
    }
}
