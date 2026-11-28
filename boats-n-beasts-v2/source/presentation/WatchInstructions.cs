using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal static class WatchInstructions
{
    const string District="WASD moves. J or left click strikes, Space dodges, K throws Lio’s hook and L signals Vara on a dungeon approach. E works a fixture or boards the ship. M opens the district map and Tab selects a destination. Use 1–4 to trade at camp.";
    internal static string For(CrewRun? run)=>run?.ActiveWatch is {} next?For(next):run switch
    {
        FlotillaWatch=>"Choose which crew gets the first berth, then take the fleet through six watches. The ship and shore parties carry their wounds. Spend provisions at the captains’ table to refit or feed either party.",
        FlotillaCommand fleet when fleet.Battle.Pilot is {} pilot=>$"You have the helm of {pilot.Company}. WASD steers. {pilot.Instructions}",
        FlotillaCommand=>"WASD steers the cutter and Shift surges. Select a friendly ship with 1–3, use Tab to choose a station and Q to give the order. G does the cutter’s work alongside a station. R recalls the selected ship, E patches the cutter and M opens the chart. Fire with Space or aim by clicking.",
        MusterLanding landing when landing.Muster.Phase==MusterPhase.Tideway=>"Walk to a ship’s pennant and use E to set its rudder. K dredges a bar. Check all three dotted courses before giving Vara the tide with L at the wheel. Reach the refuge with the consignment and board the lead vessel.",
        MusterLanding=>"Walk with WASD. E addresses skippers and works nearby stations. Use 1–3 to post their crews, J to strike, K for Lio’s hook, L for Vara and Space to dodge. M opens the yard plan. Work both sluices and release the boats through the tide gate.",
        NightPostWatch=>"Choose a connected port on the chart. Read the letter to find the recipient. A provision restores either crew or hull at an unused berth. The final assignment opens when the packet is ready.",
        PrizeWatch prize when prize.Board!=null=>"WASD moves across the deck. J or left click strikes, Shift dodges, K calls the hook and E works the hatch or objective. R uses a dressing. Return to your cutter after taking the evidence.",
        PrizeWatch=>"WASD steers, Shift surges, Space fires and Q hails a ship or works a station. Tab selects a sail. M opens the case log. Compare the public flag and rig with the stamp you read alongside. X sends an ally during an investigation.",
        UnderwaysExpedition=>"WASD moves. J or left click strikes, Space dodges, K works Lio’s line, L signals Vara and E works a fixture or doorway. Open M to inspect the deck plan. Collect the brass and blue seals, file the evidence, then take the freight gate.",
        KilnExpedition=>District,
        MigrationWatch=>"WASD steers and Shift surges. M opens the chart and Tab changes course. Play the calf’s call with 1–3, guide it to the nursery mother, and use Q to soothe it. E gathers kelp or feeds the nearby calf. R repairs the cutter.",
        PilotageVoyage=>"M opens the pilot book. Hail the named light with Q to get a second bearing. Pin the crossing on the chart and sail to it. E casts the lead, R repairs, and Q hails the tender after the final depth.",
        BluewaterVoyage=>"WASD steers and Shift surges. Space fires at a nearby threat, or click to aim a shot. Q works the active station or grapples. E repairs. Read each route before choosing a channel or refit. On fleet duty R switches escort formation.",
        SeaPassage=>"WASD steers, Q throws Lio’s line, Shift surges and E repairs. Hold Space and turn side-on for a broadside. Count the beast’s windup and use its exposed flank. Bring the salvage back to the tender.",
        _=>"WASD moves. J or left click strikes, K throws Lio’s hook, Space dodges and E works nearby fixtures. Keep an eye on the warning painted on the ground. Return to the ship after the island work is complete."
    };
}
