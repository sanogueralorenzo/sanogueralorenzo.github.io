namespace BoatsNBeasts.Core;

public sealed record IslandStory(string Island, string Speaker, string Opening, string Gift,
    CampaignOrder[] Outings);

public static partial class FarLedger
{
    static IslandStory Isle(string region, int tier, string island, string speaker, string opening, string gift,
        params CampaignOrder[] sailings) => new(island, speaker, opening, gift,
        sailings.Select(o => o with { Region = region, Tier = tier, Island = island }).ToArray());
}
