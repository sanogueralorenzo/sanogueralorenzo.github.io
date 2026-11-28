using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Choir() => CampaignArc.Create("Choir Deep","The Boats Beneath the Boats",
        "The hospital fleet travels behind a wall of singing coral. Where the official chart shows deep empty water, hundreds of patients are eating supper in their bunks.",
        "A shell with a child's two front teeth painted on the lip",
        new("Oren  /  hospital pilot","Shall the fleet be heard?",
            "Oren can send the hospital’s position to every harbor in earshot. That would bring supplies, and the registry with them. The reef singers can also lead the hospital behind a new wall of sound.",
            "Broadcast the position","Lead them through quietly",
            "Oren leans on the speaking pipe. The first answer comes from a girl asking if anyone needs bandages.",
            "The children stitch felt slippers for the galley pots. For one tide, even supper is quiet."),
        6,
        [
            Order("choir-ear",Sounding,"The Third Note","The approach to the hospital lies between two reefs that sing a tone apart. Strike the wrong shell and the channel sounds like a dinner gong.",
                "Take bearings from three shell beds and reach the hospital anchorage.","The Bass Vent","A small hand reaches through a porthole and takes the cold pear out of Jo’s pocket.",7),
            Order("choir-lung",Landing,"Ward Below the Waterline","The coral has grown through the dispensary floor. A nautilus has sealed the oxygen bell with its shell while waiting for its eggs to hatch.",
                "Clear the ward’s air passages and carry the oxygen bell outside.","Chorus Nautilus","Oren is sitting in the dispensary holding a wet towel to his head. Vara hits him with the towel and then refuses to let go.",7),
            Order("choir-air",Convoy,"Open Frequency","The first volunteer flotilla arrives with crates of clean sheets and positively no idea how to cross a reef. The registry is listening to the same frequency.",
                "Bring the volunteers into the anchorage under open signals.","The Listening Hull","One boat has brought nothing but spare reading glasses. They are the first things the ward runs out of.",7),
            Order("choir-bed",Landing,"The Missing Bed","Pip’s father went ashore to collect his back pay. The pay office offered him a berth on an examiner’s ship instead. He left his pocket watch in the locker.",
                "Unseal the payroll lockers and retrieve the examiner’s warrant.","Ward Lamprey","The warrant names Meret Gauge. Nell closes her book. She worked for Gauge before the Bellwarden took the quay.",7),
            Order("choir-sieve",Salvage,"A Thousand Teaspoons","The registry has used a sunken hospital tender to mark the border of its jurisdiction. Oren refuses to sail until the tender’s teaspoons come home.",
                "Raise the ward chests from beneath the border buoy.","Cistern Squid","Pip sorts the spoons by the initials scratched into their handles. The names match Nell’s second book.",7),
            Order("choir-bench",Blockade,"The Floating Summons","Every patient in the hospital has been summoned as an absent debtor. The court barge is coming to collect the beds.",
                "Break the summons line and follow the bailiff’s course to Sable Court.","The Brass Summons","Lio folds a summons into a paper hat for a patient who has lost her hair. She appoints herself admiral.",8)
        ],
        Order("choir-hush",Sounding,"The Quiet Convoy","The reef singers will open a way through the silence. Each hospital boat must carry the note to the next before the channel closes behind them.",
            "Take the hospital fleet through the inner voice of the reef.","Hush Snail","The last patient arrives dry. She complains that all this fuss has interrupted a perfectly good game of cards.",7));
}
