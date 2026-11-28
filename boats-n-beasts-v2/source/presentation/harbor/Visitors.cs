using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal sealed record QuayGuest(string Name, string Job, string Question, string Early,
    string First, string Second, string Reply);

public static partial class ActorArt3D
{
    internal static Node3D Visitor(int port)
    {
        var key = $"guest-{port}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry();
            int role = port switch { 0 or 3 or 5 or 9 or 11 or 14 => 1, _ => 2 };
            Crewmate(b,Vector3.Zero,role);
            Color[] cloth = [new("c76f46"),new("58897b"),new("926885"),new("459eaf"),new("6080ae"),new("c48853"),new("4f737b"),new("854c60"),new("72964d"),new("4b96aa"),new("c46d48"),new("737dba"),new("638c9d"),new("c48150"),new("72727d"),new("e0a44c")];
            Color shade = cloth[port];
            b.RoundBox(new(0,.146f,.022f),new(.117f,.114f,.068f),.014f,shade);
            b.RoundBox(new(0,.136f,-.046f),new(.081f,.099f,.008f),.006f,shade.Lightened(.17f));
            if (port is 0 or 3 or 4 or 8 or 10 or 12 or 14)
            {
                b.Sphere(new(0,.293f,0),new(.081f,.021f,.066f),shade.Lightened(.17f),10,4);
                b.Sphere(new(0,.309f,0),new(.049f,.041f,.045f),port == 4 ? Cream : shade,10,5);
            }
            if (port is 1 or 2 or 6 or 9 or 11 or 13 or 15)
            {
                b.Tube([new(.063f,.052f,0),new(.068f,.196f,-.023f),new(.066f,.38f,-.047f)],.006f,Wood,6);
                if (port == 2) b.Sphere(new(.065f,.336f,-.047f),new(.028f,.042f,.023f),new("f5b449"),8,4);
                else b.RoundBox(new(.065f,.327f,-.047f),new(.063f,.066f,.012f),.005f,port == 1 ? Cream : Brass);
            }
            if (port == 7) b.RoundBox(new(0,.18f,-.043f),new(.12f,.015f,.01f),.003f,Brass);
            b.Scale(Vector3.One * (port==1 || port==6 ? 2.35f : 3.1f));
            Cache[key] = mesh = b.Mesh(Material);
        }
        return Instance(mesh,key);
    }
}

internal static class Visitors
{
    internal static readonly QuayGuest[] All = [
        new("Sima Redthumb","Kiln pilot","Why clay?","“I learned to caulk wood with my father. When he died the registry took the yard. The mudbank, now. How do you put a lock on that?”",
            "Sima has rubbed her pilot seal so often the thumbprint is wearing away. There are forty new hands ready to replace it.",
            "Sima sets an unfired cup on the rail. It has the same mark as a ferry. “Make them kneel for their tea as well.”","Offer her the wheel"),
        new("Pell","Papermaker","What went into the paper?","“Shirts, most of it. See this blue patch? My brother wore that to a wedding. He’s going to be furious when he finds out what street he’s become.”",
            "Pell has learned the first three notes of the map flute. The fourth makes every cat leave the pier.",
            "Pell draws the mill arrows on Vara’s palms. “That way you can’t lose the way home when the paper gets wet.”","Ask for a sheet"),
        new("Ilo","Orchard keeper","Who picks the last pear?","“Nobody takes it. Last one’s for the night. You sail better when you can let your eyes get used to an ordinary dark.”",
            "The reef pilots have sent their first logbook. Ilo reads out the page where nobody wrecks, three times.",
            "A moth lays six eggs in Lio’s hat. He takes the watch bareheaded for a week.","Shade the lamp"),
        new("Anet","Pipe fitter","Why keep that tin mitten?","“When I was a girl the whole house froze. My mother put a candle under that mitten and we boiled one spoon of tea at a time.”",
            "Anet slips one more letter into the mailbag. The address reads Anyone Who Could Use One.",
            "Anet sets the last clinic bottle on the stove. Its label prescribes a hot drink for tired plumbers.","Put the kettle on"),
        new("Jo","Hospital cook","What does Pip like?","“Everything, if there’s a story in it. I once got her to eat boiled greens by telling her a crab wore them to his wedding.”",
            "Jo has borrowed a square of the roof for a napkin. The upside-down seal lands squarely in the gravy.",
            "Every bit of Jo’s apron came from a different family sail. She knows which patches need a cold wash.","Take the potato knife"),
        new("Oren","Hospital pilot","Why did you stay away?","“I was ashamed the first year. The second year there was so much to tell you I couldn’t start a letter. Then Pip asked how I expected an envelope to sail itself.”",
            "Oren tries the speaking pipe again. This time he just asks Vara how she slept.",
            "Oren and Vara sit without speaking until their tea goes cold. He makes another pot.","Make room beside Vara"),
        new("Pip","Kitchen witness","Which size ship is best?","“Depends if you’re a ship or a person. Very small ships fit in your pocket. Very big people get you down the biscuit tin.”",
            "Pip has started an index for Nell’s log. Under G for Grown-ups she has written See Arguments.",
            "Pip returns the bailiff’s hat. The roof has stopped leaking, and it was full.","Pass the biscuits"),
        new("Meret Gauge","Chart examiner","What was the name of your first boat?","“Aster. She had a blue stove. I’ve described her tonnage at a hundred hearings. Nobody ever asked me about the stove.”",
            "Gauge writes Aster in the register. Beside her name in the column for tonnage she draws a blue stove.",
            "Gauge spreads the empty chart on the planks. A child draws a blue stove and a very tall wave.","Hand her the pencil"),
        new("Uma Pike","Pool botanist","What made you follow the first root?","“I fell over it. We don't put that sort of thing in a scientific paper. I think we ought to.”","Uma has drawn each grower by the shape of their thumbprint in the earth.","Four sets of muddy boots stand outside the galley. Uma has been watering them out of habit.","Look under the saucer"),
        new("Cella Wick","Glass diver","What is a bottle orchard like below the surface?","“Green on the outside, gold on the inside. Like the first apple my sister ever stole for me.”","Cella has taught a calf to blow an air bubble large enough for a bottle to fit inside.","One pale bottle washed back to the orchard with a tiny fin print on its dusty shoulder.","Hold the bottle to the light"),
        new("Kest","Waxwing courier","What did you do with your first prize?","“We had a leak in the roof. The cup was the only thing in the house deep enough. Best use I've had out of winning.”","Kest cuts the finish ribbon and ties the two pieces where the slower wings can see them.","Kest has turned every telegram upside down. She is sketching what was under the race.","Offer her the slow chair"),
        new("Latt Minnow","Harbor bedmaker","Do the islands dream?","“Go down to the cellar with a pillow. If you wake up in a different bay, you have been in somebody else's dream.”","Latt's new beds have runners at both ends so the patient can choose the view.","Latt stitches one pocket inside each quilt. Put a letter there and it will travel with the house.","Help turn a mattress"),
        new("Islet Marr","Saturation diver","Why keep a rusty teapot in a diving bell?","“It sings in the key of my old front door. You would be amazed what sounds lead you home when there's nothing to see.”","Islet hangs a clean rag beside the families’ bell. Everyone has had a turn at the polishing.","The listening tube carries a spoon against a cup all the way up from the old kitchen.","Put an ear to the spout"),
        new("Ina","Drum keeper","What do you do with the beat between words?","“I leave it for the person who hasn't got a word in yet. My mother always knew when I was going to speak by the way I drew my breath.”","Ina has made one stick for Vara and one for Oren. They do not have to play together.","Ina hangs two drumskins opposite each other. A breath between them sets both trembling.","Wait for the next beat"),
        new("Toma Pike","Anchor captain","Is there anything you miss besides the city?","“An ordinary complaint. Somebody leaning out of a window to tell me my dinner was getting cold.”","Toma rubs the old shackle bright. There is just room for a little flowerpot in the curve.","Toma takes the evening soup around the boats in a bucket. She returns with three recipes.","Make her a place at supper"),
        new("Pip","Nursery keeper","Where does a calf put its first foot?","“Usually on mine. I used to mind. Once I found out what a grown island weighs I decided I was lucky.”","Pip has folded the blanket on Toma's big tender into a nest. The smallest calf fits inside one corner.","Pip practices the nursery song on an old whistle. She leaves more and more room for the calf to answer.","Take the second watch")
    ];
    internal static int At(CampaignLog log)
    {
        var region = log.Next?.Arc.Region ?? FarLedger.Arcs[^1].Region;
        return FarLedger.Arcs.ToList().FindIndex(arc => arc.Region == region);
    }
}
