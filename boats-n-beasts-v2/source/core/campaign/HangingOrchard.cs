using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Orchard() => CampaignArc.Create("Hanging Orchard","A Dark Enough Night",
        "The pear ticket buys a berth beneath an orchard growing from the roof of a cavern. Each ripe fruit glows. The keepers have picked the trees bare to sell the light to ships.",
        "A lantern pear wrapped in Lio’s best sock",
        new("Ilo  /  orchard keeper","Where will the last fruit shine?",
            "A single branch is coming into bloom. Sailors ask for a light on the lee reef. In the loft below, newly hatched moths wait for the scent of ripe fruit. Ilo has only one lamp crate.",
            "Light the reef","Feed the hatchlings",
            "Ilo carries the crate to a rowboat himself. The moth keepers braid him a black pilot’s sash.",
            "The nursery gets its lamp. The reef pilots lash their boats together to mark the shoal with their own silhouettes."),
        3,
        [
            Order("pear-hush",Convoy,"An Unlit Cutter","To get inside the orchard a ship must douse its lamps. Lio can smell which terraces have ripe fruit. Several of his guesses turn out to be soup.",
                "Pilot the harvest barges under the dark canopy.","Canopy Bat","A night watchman remembers Oren. He made a blanket nest for a child in a crate of winter pears.",5),
            Order("pear-nursery",Landing,"A Mouth Full of Stars","A lantern moth has cocooned the lift handles in silk. Cutting everything loose will drop the nursery into the surf. Ilo knows which threads carry the weight.",
                "Release the lift handles and lower the nursery intact.","Lantern Moth","The moth settles on Vara’s sleeve. In full light its beautiful golden wings are the color of old onions.",5),
            Order("pear-light",Sounding,"Ilo’s Lee Light","Ilo’s boat carries the lamp's wick in a jar of pear syrup. The dark reef looks like open water until the keel grinds.",
                "Survey a safe approach for the lee light.","Sweetjaw Skate","The lamp comes on just as a cutter loses its tiller pin. The reef pilot buys Ilo breakfast for a week.",6),
            Order("pear-cradle",Landing,"The Crate Marked Fruit","Pip has written the names of every vessel she saw across the counting-house floor. Someone has laid a second floor over it.",
                "Open the abandoned packing loft and copy Pip’s list.","Cradle Hornet","Most entries say boat with sail. One says MOTHER with a chimney. Nell circles the word.",6),
            Order("pear-stern",Blockade,"Light Thieves","The registry takes the night harvest aboard a lightship with every hatch painted shut. Three apprentices are still inside the lantern room.",
                "Bring down the lightship’s boom and bring the apprentices home.","Wickwing","The apprentices dismantle the lantern on your own deck. They leave a small light burning in the galley for whoever wakes first.",6),
            Order("pear-winter",Convoy,"Fruit for Winter","The ice cannery that took Pip’s mother has ordered the whole harvest. Ilo stamps the invoice in pear juice and adds the crew as bruised stock.",
                "Sail the winter fruit north before the lamps fade.","The Blackwick","The last crate tips over. Under a layer of fruit is a much-mended child’s coat bound for Whitewake Shelf.",6)
        ],
        Order("pear-feed",Hunt,"The Thin Bees","Underfed hatchlings follow a wax barge taking hive stores offshore. They will fly straight into its lantern if the crew cannot staunch the leak.",
            "Intercept the wax barge before its wake carries the brood out to sea.","Candlejack","For the first time in years, a whole terrace sets fruit overnight. Lio looks very proud of the moth on his nose.",6));
}
