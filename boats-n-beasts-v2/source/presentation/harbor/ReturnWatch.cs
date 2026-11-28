using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal static class ReturnWatch
{
    internal static (string Heading,string Story) Unfinished(CrewRun location,CampaignOrder? order)
    {
        if(location is FlotillaWatch fleet)
        {
            var passage=fleet.Passage;
            return ("The company in the lee",$"The crew of {passage.Papers.Vessel} brings the purse to Nell. The crews made {passage.Stage} of their six watches. Their two flags go back to their own piers until the next muster.");
        }
        if(location is NightPostWatch post)
        {
            if(post.OnDeck is {} active)
            {
                var voyage=Unfinished(active,order);
                return (voyage.Heading,voyage.Story+" Nell dries the packet. The next post watch will collect its seals afresh.");
            }
            return ("The packet comes back","Nell ties a fresh ribbon around the unfinished packet. The crew has brought back its purse. The post will start again from the tender.");
        }
        return location switch
        {
            UnderwaysExpedition c when c.Crawl.Lost=>
                ("Light above the hatch",$"Vara hands the last lamp up from deck {c.Crawl.Depth+1}. Nell puts the order back beside the hatch plan and counts the coins in the party’s pouch. The next descent will need fresh keys."),
            PrizeWatch p when p.Watch.Phase==PrizePhase.Lost=>
                ("The torn pennant","Lio finds the cutter in the prize fleet by the sound of Vara striking the rail. The crew comes back together with the purse. The evidence still has to come in by sea."),
            MigrationWatch m when m.Drive.Lost && m.Drive.Herd.Any(c=>c.Spirit<=0) =>
                ("The nursery keeps watch","Lio stays on the outer pier, listening. “Lost its call in the guns. Next time I'll stay close enough to feed it when it turns.” A mother answers him from the fog."),
            MigrationWatch m when m.Drive.Lost =>
                ("The mother takes the watch","Vara counts the swimmers from the lifeboat. The nursery mother shelters the scattered calves against her side. Her shepherds will have to come out again."),
            PilotageVoyage p when p.Sights.Lost =>
                ("A wet page in the pilot book","The lead came home in Lio's pocket. The chart went overboard. Nell smooths a fresh page. “Start with the light you can still see.”"),
            KilnExpedition k when k.Yard.Phase==YardPhase.Lost =>
                ("Last off the landing",k.Yard.GuardCount>0
                    ? $"Lio empties {k.Yard.Order.IslandOrRegion()} sand from his boots. “Got us both off. That thing sets its feet before it swings. Watch the feet next time.”"
                    : "The landing party crowds round the last dry stove. Vara marks the nearest camp on the chart and leaves space in the bag for a ration."),
            BluewaterVoyage b when b.Course.Phase==ChartPhase.Lost && b.Course.CrewLine.Contains("convoy",StringComparison.OrdinalIgnoreCase) =>
                ("Last boat through","Nell counts every person twice. The cargo went down astern. The next convoy will need a lookout on the rear boat and a repair kit kept for its hull."),
            BluewaterVoyage b when b.Course.Phase==ChartPhase.Lost =>
                ("The lee side of home","Vara has saved the purse in a saucepan with a tight lid. She sets it on the chart. “Next time we can take the lee channel. Nobody gives a medal for a wet hat.”"),
            ShoreExpedition s when s.Fight.Phase==QuayPhase.Lost =>
                ("Beneath the bell frame","Lio lays his hook across the table. “That ringing spot on the stones is where the hammer will fall. If we're standing beside it, we can hook the thing before it lifts its arm again.”"),
            SeaPassage s when s.Run.Leg==PassageLeg.Wrecked =>
                ("Two oars and a saucepan","Vara raises the two oars that got everyone home. Lio raises the saucepan with the silver in it. “Next time turn us side-on after the beast has spent its charge.”"),
            _=>("Back on the planks",order==null
                ?"The crew chooses a safe berth and brings its working purse ashore. Lio hangs the wet gear above the stove for the next attempt."
                :$"The sails come down by choice. Nell puts the unfinished order for {order.IslandOrRegion()} back on its peg. The crew takes its purse to the bank.")
        };
    }
    static string IslandOrRegion(this CampaignOrder o)=>o.Island.Length>0?o.Island:o.Region;
}
