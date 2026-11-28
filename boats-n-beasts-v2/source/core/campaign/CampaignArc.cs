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
        orders.Select((o,index) => o with { Region = region, Tier = tier, Postal=index==orders.Length-2 }).ToArray(), alternate with { Region = region, Tier = tier });
}

public static partial class FarLedger
{
    internal static CampaignOrder Order(string id, SeaDuty duty, string title, string brief, string objective,
        string boss, string homecoming, int legs) => new(id, "", title, brief, objective, boss, homecoming, duty, 0, legs);

    public static IReadOnlyList<CampaignArc> Arcs { get; } = [
        DeepRoutes.Open(Cinder(),CinderIsles()),
        DeepRoutes.Open(Reedglass(),ReedglassIsles()),
        DeepRoutes.Open(Orchard(),OrchardIsles()),
        DeepRoutes.Open(Whitewake(),WhitewakeIsles()),
        DeepRoutes.Open(Tangleloom(),TangleloomIsles()),
        DeepRoutes.Open(Choir(),ChoirIsles()),
        DeepRoutes.Open(Sable(),SableIsles()),
        DeepRoutes.Open(Unnumbered(),UnnumberedIsles()),
        DeepRoutes.Open(Saltstep(),SaltstepIsles()),
        DeepRoutes.Open(Bottlebrush(),BottlebrushIsles()),
        DeepRoutes.Open(Waxwing(),WaxwingIsles()),
        DeepRoutes.Open(Sleeping(),SleepingIsles()),
        DeepRoutes.Open(Tinmoon(),TinmoonIsles()),
        DeepRoutes.Open(Drumskin(),DrumskinIsles()),
        DeepRoutes.Open(Pitchwake(),PitchwakeIsles()),
        DeepRoutes.Open(Calving(),CalvingIsles())
    ];
    public static int Count => Arcs.Sum(arc => arc.Length);
    static readonly Dictionary<string,CampaignOrder> ById=Arcs.SelectMany(arc=>arc.Orders.Append(arc.Alternate)
        .Concat(arc.Islands.SelectMany(island=>island.Outings))).ToDictionary(order=>order.Id,StringComparer.Ordinal);
    public static CampaignOrder Find(string id)=>ById[id];
}
