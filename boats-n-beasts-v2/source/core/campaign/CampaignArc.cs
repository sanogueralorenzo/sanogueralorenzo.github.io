namespace BoatsNBeasts.Core;

public sealed record Hearing(string Speaker, string Question, string Testimony,
    string First, string Second, string FirstResult, string SecondResult);

public sealed record CampaignArc(string Region, string Title, string Lead, string Keepsake,
    Hearing Hearing, CampaignOrder[] Orders, CampaignOrder Alternate)
{
    public IslandStory[] Islands { get; init; } = [];
    public int Length => Orders.Length + Islands.Sum(i => i.Outings.Length);
    public const int Fork = 2;

    public CampaignOrder OrderAt(int stop, bool second) => stop == Fork && second ? Alternate : Orders[stop];

    internal static CampaignArc Create(string region, string title, string lead, string keepsake, Hearing hearing,
        int tier, CampaignOrder[] orders, CampaignOrder alternate) => new(region,title,lead,keepsake,hearing,
        orders.Select(o => o with { Region = region, Tier = tier }).ToArray(), alternate with { Region = region, Tier = tier });
}

public static partial class FarLedger
{
    internal static CampaignOrder Order(string id, SeaDuty duty, string title, string brief, string objective,
        string boss, string homecoming, int legs) => new(id, "", title, brief, objective, boss, homecoming, duty, 0, legs);

    public static IReadOnlyList<CampaignArc> Arcs { get; } = [Cinder() with { Islands = CinderIsles() }, Reedglass(), Orchard(), Whitewake(), Tangleloom(), Choir(), Sable(), Unnumbered() with { Islands = UnnumberedIsles() }];
    public static int Count => Arcs.Sum(arc => arc.Length);
    public static CampaignOrder Find(string id) => Arcs.SelectMany(arc =>
        arc.Orders.Append(arc.Alternate).Concat(arc.Islands.SelectMany(i => i.Outings))).First(order => order.Id == id);
    public static (CampaignArc Arc, int Stop)? Locate(int completed)
    {
        if (completed < 0) return null;
        foreach (var arc in Arcs)
        {
            if (completed < arc.Length) return (arc, completed);
            completed -= arc.Length;
        }
        return null;
    }
}
