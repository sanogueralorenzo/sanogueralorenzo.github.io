using System.Numerics;

namespace BoatsNBeasts.Core;

public enum InnerWork { Casting, Floodgate, Counterpoise, Loom }
public enum WorksStage { Mouth, Transfer, Sentries, Archive, TwoHands, KeyRoom, Stairs }
public sealed record HiddenWorks(string Title,string SafeRoom,string RiskRoom,string Archive,string Key,string Apparatus,
    string Entry,string Discovery,string Exit,InnerWork Mechanism)
{
    public static HiddenWorks? On(string id)=>id switch
    {
        "knuckle-bench"=>new("The Upturned Dock","Hull lift","Tar pit","Dita’s loft","keel key","rowlock press",
            "Dita’s grandfather drove the first keel in from below. Lio finds the handline he used to climb out.",
            "Two pencil outlines meet on the ceiling. Dita was seven when she traced her palm inside her grandfather’s. Both hands have to steady a reversible keel.",
            "The rowlock press lets go. Dita can feel the dry dock turn gently under her feet.",InnerWork.Casting),
        "chair-locker"=>new("The School Below the Sluice","Chalk stair","Ink sump","Classroom","drawer key","school sluice",
            "Eda turns the bottom step upside down. A fish skeleton in a jar marks the entrance to the last classroom above flood level.",
            "Under the teacher’s desk are nine peg holes and ten names. Eda had walked the tenth child over the border before roll call every morning.",
            "The sluice coughs up a brass drawer key. Eda puts it inside the attendance book.",InnerWork.Floodgate),
        "graft-half"=>new("The Graft Galleries","Nurse lift","Pruning chute","Growth rings","graft wedge","crown balance",
            "The oldest graft has swallowed the stairs. Hennel points out where the roots have grown around a little service lift.",
            "A row of marks records the twins’ height on opposite faces of one branch. A band of cloth joins the last two measurements.",
            "The counterpoise settles. Two shoots lean away from each other without cracking the trunk.",InnerWork.Counterpoise),
        "mitten-cellar"=>new("The Onion House","Blanket hoist","Steam scar","Potting shed","cellar key","stove shoe",
            "Mittens are drying on an iron rung under the floor. The crew follows their warm drips down to the first lamp.",
            "Each onion bed has a tin lid for a nameplate. Tavi recognizes the thumb dent his mother made when she first lifted the night route.",
            "The shoe seats in the stove. Thirteen little green shadows appear on the cellar ceiling.",InnerWork.Casting),
        "button-seam"=>new("The Inside Catch","Spool lift","Needle trench","Pattern room","half-button","two-sided clasp",
            "The night shift marked its way home with buttons sewn into the plaster. Sib finds the first one under her thumbnail.",
            "The oldest pattern shows two open hands on opposite sides of the same door. A worker crossed out the drawing of a key and stitched a sleeve over it.",
            "The clasp opens in two directions. Sib holds a hand out to somebody she has only seen in silhouette.",InnerWork.Loom),
        "cot-thread"=>new("The Air Behind the Ward","Linen cradle","Breath sump","Night desk","vent key","lung valve",
            "Reva keeps a clean strip of cotton at every bend in the duct. Follow the strips that still move, she tells the crew.",
            "The night log takes a whole page to describe one patient squeezing Reva’s hand. Her reply is written as a slight correction to the air pressure.",
            "The vent opens. In the ward above, a strip of linen lifts as though someone had taken a breath.",InnerWork.Floodgate),
        "halfpenny-glass"=>new("The Hall of Second Crossings","Evidence lift","Mirror drain","Fare counter","witness key","counterweight",
            "Ada’s reflection reaches the turnstile just after she does. The second click has been collecting a fare for twenty years.",
            "Ada’s husband drew his ferry on a scrap of mirror backing. Under the boat is a seated figure with one hand tucked round a halfpenny.",
            "The counterweight comes down once. Ada counts only one return on the dial.",InnerWork.Counterpoise),
        "noon-clock"=>new("The Lost Interval","Minute lift","Escapement pit","Pantry ledger","pantry spring","double escapement",
            "Hester has been keeping the lost hour in a pantry with a wire screen. Something inside has been eating the hands off her clocks.",
            "Jo’s name is written at four different heights on the birthday shelf. Hester gave her a little more reach every time she came back hungry.",
            "Two hands meet at noon. The door opens onto a minute Hester thought she had thrown away.",InnerWork.Loom),
        _=>null
    };

    public string[] RoomNames=>["Landing",SafeRoom,RiskRoom,"Upper stair",Archive,"Vara’s drum","Lio’s bracket","Transfer lift",Apparatus];
    public static (Vector4[] Positions,(int A,int B)[] Edges) Chambers(IslandClimate climate)
    {
        Vector2[] rooms=climate switch
        {
            IslandClimate.Kiln=>[new(0,12),new(-9,7),new(9,6),new(6,-28),new(0,-3),new(8,-12),new(-8,-10),new(-12,-2),new(2,-20)],
            IslandClimate.Delta=>[new(-10,10),new(-15,1),new(-1,10),new(13,-15),new(-2,-1),new(6,1),new(-7,-11),new(-16,-8),new(5,-13)],
            IslandClimate.Orchard=>[new(-2,14),new(-12,10),new(7,8),new(-9,-25),new(-2,-2),new(7,-10),new(-13,-9),new(-14,0),new(-2,-18)],
            IslandClimate.Shelf=>[new(1,13),new(-9,11),new(9,5),new(2,-28),new(0,-4),new(9,-12),new(-10,-10),new(-13,1),new(1,-19)],
            IslandClimate.Loom=>[new(-14,7),new(-17,-3),new(-4,8),new(18,-19),new(-3,-3),new(7,-3),new(-7,-14),new(-13,-12),new(8,-15)],
            IslandClimate.Reef=>[new(8,12),new(-3,13),new(14,2),new(2,-26),new(4,-3),new(12,-11),new(-5,-9),new(-9,2),new(3,-18)],
            IslandClimate.Court=>[new(-10,12),new(-18,5),new(0,10),new(13,-18),new(-5,-2),new(5,-2),new(-9,-12),new(-17,-5),new(4,-14)],
            _=>[new(0,16),new(-10,10),new(10,10),new(-2,-27),new(0,-2),new(10,-9),new(-11,-9),new(-13,0),new(0,-18)]
        };
        Vector4[] places=rooms.Select((p,i)=>new Vector4(p.X,p.Y,i==3?4.1f:i==8?3.78f:3.15f,i==8?3.05f:2.65f)).ToArray();
        return(places,[(0,1),(0,2),(1,7),(7,4),(2,4),(4,5),(4,6),(5,8),(6,8),(8,3)]);
    }
}
