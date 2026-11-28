namespace BoatsNBeasts;

internal static class WatchInstructions
{
    const string District="WASD moves. J or left click strikes, Space dodges, K throws Lio’s hook and L signals Vara on a dungeon approach. E works a fixture or boards the ship. M opens the district map and Tab selects a destination. Use 1–4 to trade at camp.";
    internal static string For(CrewRun? run)=>run switch
    {
        NightPostWatch post when post.OnDeck!=null=>For(post.OnDeck),
        NightPostWatch=>"Choose a connected port on the chart. Read the letter to find the recipient. A provision restores either crew or hull at an unused berth. The final assignment opens when the packet is ready.",
        PrizeWatch prize when prize.Child!=null=>For(prize.Child),
        PrizeWatch prize when prize.Board!=null=>"WASD moves across the deck. J or left click strikes, Shift dodges, K calls the hook and E works the hatch or objective. R uses a dressing. Return to your cutter after taking the evidence.",
        PrizeWatch=>"WASD steers, Shift surges, Space fires and Q hails a ship or works a station. Tab selects a sail. M opens the case log. Compare the public flag and rig with the stamp you read alongside. X sends an ally during an investigation.",
        UnderwaysExpedition c when c.Crawl.Surface!=null=>District,
        UnderwaysExpedition=>"WASD moves. J or left click strikes, Space dodges, K works Lio’s line, L signals Vara and E works a fixture or doorway. Open M to inspect the deck plan. Collect the brass and blue seals, file the evidence, then take the freight gate.",
        KilnExpedition=>District,
        MigrationWatch=>"WASD steers and Shift surges. M opens the chart and Tab changes course. Play the calf’s call with 1–3, guide it to the nursery mother, and use Q to soothe it. E gathers kelp or feeds the nearby calf. R repairs the cutter.",
        PilotageVoyage=>"M opens the pilot book. Hail the named light with Q to get a second bearing. Pin the crossing on the chart and sail to it. E casts the lead, R repairs, and Q hails the tender after the final depth.",
        BluewaterVoyage=>"WASD steers and Shift surges. Space fires at a nearby threat, or click to aim a shot. Q works the active station or grapples. E repairs. Read each route before choosing a channel or refit. On fleet duty R switches escort formation.",
        SeaPassage=>"WASD steers, Q throws Lio’s line, Shift surges and E repairs. Hold Space and turn side-on for a broadside. Count the beast’s windup and use its exposed flank. Bring the salvage back to the tender.",
        _=>"WASD moves. J or left click strikes, K throws Lio’s hook, Space dodges and E works nearby fixtures. Keep an eye on the warning painted on the ground. Return to the ship after the island work is complete."
    };
}
