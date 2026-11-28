using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    void FleetRegister(int page)
    {
        var log=Ledger.Campaign;
        var filed=log.Voyages.Select(FarLedger.Find).Where(o=>o.Flotilla).ToArray();
        if(filed.Length==0){Close();return;}
        page=Math.Clamp(page,0,filed.Length-1);
        var order=filed[page];var p=order.Articles!;
        Open($"THE FLEET REGISTER    /    {order.Region.ToUpperInvariant()}    /    {page+1} OF {filed.Length}",
            p.Vessel,$"{p.Captain}   ·   {p.Home}\n{log.Homecoming(order)}");
        if(page>0)Choice("Previous launch",()=>FleetRegister(page-1));
        if(page+1<filed.Length)Choice("Next launch",()=>FleetRegister(page+1));
        Choice("See the charter",()=>
        {
            Open("THE ARTICLES    /    "+p.ConsortHome.ToUpperInvariant(),p.Vessel+" and "+p.ConsortVessel,
                $"{order.Brief} {p.Consort} signed alongside {p.Captain}.");
            Choice("Return to the register",()=>FleetRegister(page),true);
        });
        Choice("Leave the register",Close,true);
    }
}

internal partial class QuayView
{
    readonly List<(Node3D Ship,Vector3 Berth)> launches=[];
    void MoorFleet()
    {
        var orders=Ledger.Campaign.Voyages.Reverse().Select(FarLedger.Find).Where(o=>o.Flotilla).Take(2);
        foreach(var order in orders)
        {
            var p=order.Articles!;int k=launches.Count;
            var hull=(BoatKind)((order.Tier+p.Slot)%3);
            var boat=ActorArt3D.Boat(hull,[1,0,0,0,hull==BoatKind.Trawler?1:0,hull==BoatKind.Mage?1:0]);
            var berth=k==0?new Vector3(-4.27f,0,3.76f):new Vector3(4.7f,0,2.65f);
            boat.Name="FleetLaunch"+k;boat.Position=berth;boat.Scale=Vector3.One*.58f;
            boat.Rotation=new(0,k==0?.91f:-.78f,0);ActorArt3D.MountCarving(boat,order.Tier-1);
            AddChild(boat);launches.Add((boat,berth));
        }
    }
    void RideMoorings()
    {
        for(int i=0;i<launches.Count;i++)
        {
            var (hull,berth)=launches[i];
            hull.Position=berth+Vector3.Up*(.025f*Mathf.Sin(clock*1.36f+i));
            ActorArt3D.AnimateBoat(hull,clock+i,0,0);
        }
    }
}
