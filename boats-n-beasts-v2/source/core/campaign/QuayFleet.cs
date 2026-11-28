namespace BoatsNBeasts.Core;

public sealed record HullPlan(BoatKind Kind,string Name,string Description,int Silver,int Ports);
public static class QuayFleet
{
    public static readonly HullPlan[] Plans=[
        new(BoatKind.Cutter,"The Last Light cutter","Light on the helm. Its gun crew loads 65% faster under surge.",0,0),
        new(BoatKind.Trawler,"The Mudlark","A slower, broad-beamed trawler with a 155-point hull. Its settling wheel clears nearby shots and its drag net stirs a damaging whirlpool.",360,1),
        new(BoatKind.Mage,"The Wisp Lantern","A 115-point pilot yawl. Wisp lights chase nearby beasts while the gun crew works the broadside.",620,3)
    ];
    public static readonly string[] Carvings=["Clay swallow","Paper coot","Lantern pear","Tin mitten","Tailor’s shuttle","Singing shell","Copper halfpenny","Compass rose",
        "Walking root","Green bottle","Winged seal","Dreaming shoal","Diver’s bell","Dancing drum","Black anchor","Young reef"];
    public static int Price(int index)=>90+index*45;
    public static HarborLedger Commission(this HarborLedger ledger,HullPlan hull)
    {
        if(!ledger.Dedicated||!Plans.Contains(hull))return ledger;
        if(hull.Kind==BoatKind.Cutter || ledger.Hulls.Contains(hull.Kind))return ledger with{ Vessel=hull.Kind };
        if(ledger.Silver<hull.Silver || ledger.Campaign.SettledPorts().Count()<hull.Ports)return ledger;
        return ledger with{Vessel=hull.Kind,Hulls=[..ledger.Hulls,hull.Kind],Silver=ledger.Silver-hull.Silver};
    }
    public static HarborLedger Carve(this HarborLedger ledger,int index)
    {
        if(index<0)return ledger with { Figurehead=-1 };
        if(index>=Carvings.Length||index>=ledger.Campaign.SettledPorts().Count())return ledger;
        if(ledger.Carvings.Contains(index))return ledger with{ Figurehead=index };
        int cost=Price(index);
        return ledger.Silver<cost?ledger:ledger with{ Figurehead=index,Silver=ledger.Silver-cost,Carvings=[..ledger.Carvings,index] };
    }
}
