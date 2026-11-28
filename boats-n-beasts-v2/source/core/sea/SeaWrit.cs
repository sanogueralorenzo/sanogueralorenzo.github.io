namespace BoatsNBeasts.Core;

public sealed record SeaWrit(string Cargo, string Berth, int Lighters = 0, bool Quiet = false, bool Delicate = false)
{
    public static SeaWrit For(CampaignOrder order) => order.Id switch
    {
        "cinder-pilot" => new("unfired ferry", "the cool slips", 3),
        "cinder-pilots" => new("pilots’ seal", "the examination line", 1),
        "cinder-potters" => new("raw-cargo tag press", "the potters’ tender", Delicate:true),
        "cinder-hulk" => new("dispatch box", "the fire grate lighter", Delicate:true),
        "cinder-float" => new("citizen ferry", "the launch slips", 3),
        "reed-sound" => new("mill-stair sounding", "the submerged steps"),
        "reed-flute" => new("ferryman’s map flute", "the ferry families", 2, Quiet:true),
        "reed-strike" => new("inspection paint pot", "the mill gate"),
        "reed-scow" => new("striped datum board", "the mill stairs"),
        "reed-press" => new("passage stubs", "the rag pickers", Delicate:true),
        "pear-hush" => new("unlit harvest barge", "the dark canopy", 2, Quiet:true),
        "pear-light" => new("keeper’s wick", "the lee light"),
        "pear-feed" => new("leaking wax drum", "the nursery terraces"),
        "pear-stern" => new("apprentices’ lightship", "the lantern room", Quiet:true),
        "pear-winter" => new("winter pear crate", "the northbound slips", 2, Delicate:true),
        "ice-post" => new("dry mail bag", "the warm leads", Delicate:true),
        "ice-sled" => new("mail sledge", "the broken shelf", 1),
        "ice-tonic" => new("clinic tonic", "the infirmary pier", Delicate:true),
        "ice-fee" => new("medicine allotment drum", "the runners’ gate"),
        "ice-lights" => new("Oren’s red buoy", "the thermal lead"),
        "loom-wind" => new("wind reading", "the suspended mills"),
        "loom-roof" => new("roof mooring", "the strikers’ pier"),
        "loom-fleet" => new("family sailboat", "the loom basin", 3),
        "loom-ferry" => new("Jo’s kitchen barge", "the supper mooring", 1, Delicate:true),
        "loom-song" => new("tuned wooden bobbin", "the spinning shed"),
        "choir-ear" => new("third-note reading", "the listening raft"),
        "choir-air" => new("hospital air lighter", "the breathing dock", 1, Delicate:true),
        "choir-hush" => new("quiet channel bearing", "the hospital berth", Quiet:true),
        "choir-sieve" => new("patients’ teaspoons", "the hospital pantry", Delicate:true),
        "choir-bench" => new("summons barge", "the hearing pier"),
        "sable-writ" => new("warrant folio", "the court steps"),
        "sable-ink" => new("wet ink ledger", "the archive lighter", Delicate:true),
        "sable-pip" => new("witness skiff", "the window fleet", 3, Quiet:true),
        "sable-race" => new("court barge", "the appeal dock", 2),
        "sable-north" => new("buried needle", "the compass berth"),
        "north-tow" => new("harbor pilot", "the fleet anchorage", 3),
        "north-index" => new("signed harbor mark", "the open index", Delicate:true),
        "north-white" => new("public bearing", "the pilots’ knot"),
        "north-wake" => new("Last Light’s lamp", "the homebound fleet"),
        "north-return" => new("common compass boat", "Last Light Quay", 3),
        _ => new(order.Duty switch
        {
            SeaDuty.Convoy => "local ferry", SeaDuty.Salvage => "chartered cargo", SeaDuty.Hunt => "quarry",
            SeaDuty.Sounding => "pilot’s mark", _ => "port signal"
        }, string.IsNullOrEmpty(order.Island) ? order.Region : order.Island,order.Duty == SeaDuty.Convoy ? 3 : 0)
    };
}
