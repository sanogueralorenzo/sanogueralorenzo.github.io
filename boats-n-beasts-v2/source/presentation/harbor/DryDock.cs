using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    void DryDock()
    {
        var current=QuayFleet.Plans[(int)Ledger.Vessel];
        Open("THE DRY DOCK","Choose a ship",$"{current.Name} is berthed at the quay. Each vessel retains a deck gun for opening sea lanes. Commission a hull here or bring an owned ship alongside.");
        foreach(var plan in QuayFleet.Plans)Choice(plan.Name,()=>InspectHull(plan),plan==current);
        if(Ledger.Campaign.SettledPorts().Any())Choice("The carver’s bench",()=>Carver(Math.Max(0,Ledger.Figurehead)));
        Choice("Back to the quay",Close);
    }
    void InspectHull(HullPlan plan)
    {
        bool owned=plan.Kind==BoatKind.Cutter || Ledger.Hulls.Contains(plan.Kind);
        var spec=BoatSpec.For(plan.Kind);int settled=Ledger.Campaign.SettledPorts().Count();
        string terms=owned?"This ship belongs to the crew.":settled<plan.Ports?$"Its builders come to Last Light after {plan.Ports} regions have settled.":$"The shipwrights ask {plan.Silver} silver for the finished hull.";
        Open("THE SHIPWRIGHTS",plan.Name,$"{plan.Description}  {spec.Hull:0} base hull · {spec.Speed:0} sailing speed.  {terms}");
        if(owned || settled>=plan.Ports && Ledger.Silver>=plan.Silver)
            Choice(owned?"Bring her alongside":$"Commission for {plan.Silver} silver",()=>{UpdateLedger(Ledger.Commission(plan));DryDock();},true);
        Choice("Inspect the other hulls",DryDock);
    }
    void Carver(int index)
    {
        int count=Ledger.Campaign.SettledPorts().Count();if(count==0){DryDock();return;}
        int cost=QuayFleet.Price(index);bool owned=Ledger.Carvings.Contains(index);
        var arc=FarLedger.Arcs[index];
        Open("THE CARVER’S BENCH    /    "+arc.Region.ToUpperInvariant(),QuayFleet.Carvings[index],
            $"The returning pilots brought a pattern from {arc.Region}. The carver mounts it on the bow of the active ship. "+(owned?"The carving is yours.":$"Cutting and gilding cost {cost} silver."));
        if(owned||Ledger.Silver>=cost)Choice(owned?"Mount the carving":$"Commission   ·   {cost} silver",()=>{UpdateLedger(Ledger.Carve(index));DryDock();},true);
        if(count>1)Choice("Next pattern",()=>Carver((index+1)%count));
        if(Ledger.Figurehead>=0)Choice("Clear the bow",()=>{UpdateLedger(Ledger.Carve(-1));DryDock();});
        Choice("Return to the dock",DryDock);
    }
}

public static partial class ActorArt3D
{
    public static void MountCarving(Node3D boat,int index)
    {
        if(index<0||index>=QuayFleet.Carvings.Length)return;
        var b=new ActorGeometry();Color gilt=new("f2bd70"),ivory=new("ffe3ab");
        Color[] shades=[new("d07f55"),new("528771"),new("dd9b53"),new("72afbe"),new("a17ca2"),new("b87f65"),new("bc824f"),new("578589")];
        var dye=shades[index%8];
        b.Tube([new(0,0,0),new(0,.13f,-.045f),new(0,.18f,-.08f)],[.07f,.06f,.035f],gilt,7);
        var center=new Vector3(0,.20f,-.075f);
        switch(index)
        {
            case 0:case 1:case 10:
                b.Sphere(center,new(.06f,.07f,.10f),dye,8,5);
                b.Sphere(center+new Vector3(0,.073f,-.06f),new(.054f,.059f,.055f),ivory,7,4);
                for(int d=-1;d<=1;d+=2)b.Polygon([center,center+new Vector3(d*.19f,.135f,.09f),center+new Vector3(d*.09f,.025f,.04f)],gilt,Vector3.Up);
                break;
            case 2:case 5:case 11:case 15:
                b.Sphere(center,new(.105f,.115f,.12f),dye,8,6);
                b.Tube([center+Vector3.Up*.08f,center+new Vector3(.05f,.22f,.02f)],[.025f,.012f],gilt,6);
                b.Polygon([center+Vector3.Up*.14f,center+new Vector3(-.12f,.24f,.03f),center+new Vector3(-.03f,.21f,.015f)],ivory,Vector3.Back);
                break;
            case 3:case 4:case 6:case 13:
                b.RoundBox(center,new(.16f,.185f,.073f),.037f,dye);
                for(int k=-1;k<=1;k++)b.Tube([center+new Vector3(-.071f,k*.055f,-.041f),center+new Vector3(.071f,k*.055f,-.041f)],.009f,gilt,5);
                break;
            case 9:case 12:
                b.Tube([center-Vector3.Up*.07f,center+Vector3.Up*.025f,center+Vector3.Up*.115f,center+Vector3.Up*.16f],[.10f,.098f,.042f,.039f],dye,9);
                b.Ring(center+Vector3.Up*.132f,.048f,.012f,gilt);
                break;
            default:
                for(int j=0;j<5;j++)
                {
                    float a=j*Mathf.Tau/5;
                    var to=new Vector3(Mathf.Sin(a),Mathf.Cos(a),0);
                    b.Tube([center,center+to*.13f+Vector3.Forward*.035f,center+to*.16f+Vector3.Up*.035f],[.029f,.027f,.009f],j%2==0?ivory:gilt,6);
                }
                break;
        }
        var carving=new MeshInstance3D{Mesh=b.Mesh(Material),Position=new(0,.21f,-.83f),Scale=Vector3.One*1.22f};
        boat.GetChild<Node3D>(0).AddChild(carving);
    }
}
