using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class ConvoyLanding
{
    public int FreightStep{get;private set;}public int Carrier{get;private set;}=-1;
    public bool CargoDelivered{get;private set;}public bool SalvagedLoose{get;private set;}
    public Vector2 Freight{get;private set;}
    public string CargoName=>Order.Articles?.Cargo??Region.Cargo;
    public string CargoSignal=>Order.Articles?.Signal??Region.Marks[1]+" on the rim";
    public string Refuge=>Order.Articles?.Refuge??Region.Districts[^1];
    public int SealNumber=>(int)((uint)Seed%3);
    public string SealText(int i)=>i==SealNumber?CargoSignal:i==(SealNumber+1)%3?"a white cord tied twice":"a chalk gull under the rim";
    public Vector2 SealSite(int index)
    {
        var yard=Plan.Patches.MinBy(p=>Vector2.DistanceSquared(p.Center,Plan.Wayhouse))!;
        return yard.Closest(Plan.Wayhouse+new Vector2(MathF.Cos(index*2.1f)*1.62f,MathF.Sin(index*2.1f)*1.33f));
    }
    public bool CargoAdrift=>Carrier>=0&&Boats[Carrier].Hull<=0&&!CargoDelivered;
    public string CargoInstruction=>FreightStep switch{
        0=>$"Follow the warehouse tally or hook the rival’s exposed tow to recover {CargoName}",
        1=>$"Find the consignment marked by {CargoSignal}",
        2 when Foes.Count>0=>"Drive the rival tow crew away from the consignment",
        2=>$"Tow {CargoName} to the pennant of the boat that will carry it",
        _=>$"{Boats[Carrier].Name} has the consignment. Call the convoy to the tide gate"
    };
    public IEnumerable<(Vector2 At,string Label)> FreightMarks()
    {
        if(FreightStep==0){yield return(Plan.Wayhouse,"E  Read warehouse tally");yield return(Plan.Pocket,"K  Catch rival’s tow");}
        else if(FreightStep==1)for(int i=0;i<3;i++)yield return(SealSite(i),"E  "+SealText(i));
        else if(FreightStep==2&&Foes.Count>0)foreach(var f in Foes)yield return(f.Position,"Break the rival’s claim");
        else if(FreightStep==2)foreach(var b in Boats.Where(b=>b.Hull>0))yield return(Launch(b.Index),"E  Stow aboard "+b.Name);
        else yield return(Plan.Gate,"E  Call the convoy");
    }
    bool FreightAction(char key)
    {
        if(Phase==MusterPhase.Embark&&CargoAdrift)
        {
            if(key=='K'&&!SalvagedLoose&&Near(Launch(Carrier),1.63f)){Tether(Launch(Carrier));SalvagedLoose=true;Say("Lio raises the sealed consignment from the grounded hull. Take it to another skipper’s line.");return true;}
            if(key=='E'&&SalvagedLoose)
            {
                var spare=Boats.Where(b=>b.Hull>0).MinBy(b=>Vector2.DistanceSquared(Player,Launch(b.Index)));
                if(spare!=null&&Near(Launch(spare.Index),1.16f)){Carrier=spare.Index;SalvagedLoose=false;Say($"{spare.Skipper} catches the consignment and makes it fast.");return true;}
            }
            return false;
        }
        if(Phase==MusterPhase.Embark&&Last&&!CargoDelivered&&Carrier>=0&&key=='L'&&Near(Launch(Carrier),1.35f))
        {
            CargoDelivered=true;Silver+=4;Flash=.43f;Say($"{Boats[Carrier].Skipper} lowers {CargoName} into the waiting hands at {Refuge}.");return true;
        }
        if(Phase!=MusterPhase.Consign)return false;
        if(FreightStep==0)
        {
            if(key=='E'&&Near(Plan.Wayhouse,1.22f)){FreightStep=1;Say($"The manifest names {CargoName}. The shipper marked the correct case with {CargoSignal}.");return true;}
            if(key=='K'&&Near(Plan.Pocket,1.63f)){FreightStep=2;Freight=Plan.Pocket;Tether(Freight);Spawn(YardBeast.Porter,Plan.Pocket+Vector2.UnitX);Spawn(YardBeast.Slinger,Plan.Pocket-Vector2.UnitY);Silver+=3;Say("Lio catches the exposed tow. Its handlers come back over the bank for the line.");return true;}
        }
        if(FreightStep==1&&key=='E')
        {
            int mark=Enumerable.Range(0,3).MinBy(i=>Vector2.DistanceSquared(Player,SealSite(i)));
            if(!Near(SealSite(mark),.98f))return false;
            if(mark!=SealNumber)Say($"This case bears {SealText(mark)}. The consignment has {CargoSignal}.");
            else{FreightStep=2;Freight=SealSite(mark);Say($"The marking matches. Carry {CargoName} to the upper pennants and choose a hull.");}return true;
        }
        if(FreightStep==2&&Foes.Count==0&&key=='E')
        {
            var ship=Boats.Where(b=>b.Hull>0).MinBy(b=>Vector2.DistanceSquared(Player,Launch(b.Index)));
            if(ship==null||!Near(Launch(ship.Index),1.15f)||Vector2.Distance(Freight,Launch(ship.Index))>2.15f)return false;
            Carrier=ship.Index;FreightStep++;if(ship.Role==MusterRole.Fortify)ship.Timbers++;if(ship.Role==MusterRole.Salvage)ship.Stores++;if(ship.Role==MusterRole.Escort)ship.People++;
            Say($"{ship.Skipper} signs for {CargoName}. The pennant stays with that hull to {Refuge}.");return true;
        }
        if(FreightStep==3&&key=='E'&&Near(Plan.Gate,1.24f)){BeginGuard();return true;}
        return false;
    }
}
