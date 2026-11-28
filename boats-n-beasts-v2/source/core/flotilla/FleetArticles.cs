namespace BoatsNBeasts.Core;

public sealed record FleetArticles(string Vessel,string Captain,string Consort,string ConsortVessel,string Refuge,
    string Signal,string Cargo,string Home,string ConsortHome,string Answer,string Pledge,string Berth,int Slot);

internal sealed record FleetHull(string Vessel,string Refuge,string Cargo,string Signal,string Rival,string Need,string Answer,string Pledge,string Berth);

internal static partial class FreeFleet
{
    static readonly FleetHull[] CinderFleet=[
        new("Wrong Side Up","the flooded roof road","a cradle of soaking lime","two crossed spoons","Admiral Whitewash",
            "Dita’s first flood ferry is upside down by design. The roof masons can keep their houses standing if the boat reaches them before the wet lime sets. A whitening barge is buying the houses for the price of their chalk.",
            "A spoon will stand up in the first good mortar. Dita leaves hers there. A roof that spent years serving as a floor gets its first rain.",
            "The masons cut low doors for the next boat. Dita gives its coxswain the other spoon.",
            "The pilots set two high marks above the wet plaster. Dita nails a reversible sign between them."),
        new("The Spare Tooth","the flood bakery","the night bakers’ key blanks","a twist of red dough","The Crumb Sheriff",
            "Bram has kept the keys to every evacuated house. The bakery is the only dry place he can lay them out. Someone has entered the town in the tollbook as a single empty building.",
            "The flour picks out a different thumbprint on every key. Bram has the owners choose their own doors.",
            "The first owner to return puts a kettle on for the others. She keeps the biggest key for the smallest child.",
            "The pilots put the keys on a spare anchor ring. Each turn of the tide knocks a different house against the bell."),
        new("Laundry Weather","the twin smoke stairs","a mastful of damp distress flags","one striped stocking over two plain ones","The Weather Vane",
            "Uli and Una discover that somebody has been copying their warnings an hour late and selling them to inbound boats. They need an entire fleet to hoist a correction large enough to see over the kiln smoke.",
            "A skipper who had been sheltering from yesterday’s weather takes down her roof sail. The twins sign today’s forecast with a wet sock.",
            "On washing day the warning line belongs to everybody. The twins take turns bringing pegs.",
            "The riggers splice a separate halyard for corrections. It runs lower than the official flag and is easier to read."),
        new("Eggcup Express","the hatchlings’ tide gate","a tray of eggs warm from the kiln","three taps and a shell held to the ear","The Brood Receiver",
            "Fen says an egg has paid its passage when the one inside is ready to hatch. A receiver has started weighing them for freight. The smallest has begun tapping the beat of the scale.",
            "At the tide gate the smallest egg hatches first. Its new owner tries to weigh the pieces. Fen takes the scale pan to use as a bath.",
            "The pilots let each hatchling pick a boat. The one that chooses the receiver gets a better offer from his boot.",
            "The yard cuts a step low enough for the last hatchling. Before long several grandfathers are using it too.")
    ];
    internal static CampaignOrder Muster(CampaignArc arc,FleetHull[] hulls,int slot)
    {
        var home=arc.Islands[slot];int partner=(slot+1+(arc.Orders[0].Tier%2))%4;var consort=arc.Islands[partner];
        var hull=hulls[slot];
        var papers=new FleetArticles(hull.Vessel,home.Speaker,consort.Speaker,hulls[partner].Vessel,hull.Refuge,hull.Signal,
            hull.Cargo,home.Island,consort.Island,hull.Answer,hull.Pledge,hull.Berth,slot);
        return new(home.Outings[0].Id+"-flotilla",arc.Region,hull.Vessel,hull.Need,
            $"Bring {hull.Cargo} to {hull.Refuge}. Muster the crews of {home.Island} and {consort.Island} and see their boats safely home.",
            hull.Rival,hull.Answer,SeaDuty.Convoy,arc.Orders[0].Tier,6){Articles=papers,Flotilla=true};
    }
    internal static CampaignArc Charter(CampaignArc arc)
    {
        int tier=arc.Orders[0].Tier;
        var company=tier==1?CinderFleet:tier<=8?InnerFleet[tier-2]:OuterFleet[tier-9];
        var fleet=Enumerable.Range(0,4).Select(i=>Muster(arc,company,i));
        return arc with { Orders=[..arc.Orders[..^2],..fleet,..arc.Orders[^2..]] };
    }
    public static CampaignOrder CinderCharter()=>FarLedger.Arcs[0].Orders.First(order=>order.Flotilla);
}
