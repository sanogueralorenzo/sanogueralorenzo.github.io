using System.Numerics;

namespace BoatsNBeasts.Core;

public readonly record struct PostLane(int From,int To,SeaDuty Duty);
public sealed class PostalCircuit
{
    public CampaignOrder Order { get; }
    public CampaignArc Arc { get; }
    public int Island { get; }
    public bool Public => Island<0;
    public int Pickup { get; }
    public int Port { get; private set; }
    public int Destination { get; private set; } = -1;
    public int Legs { get; private set; }
    public int Purse { get; private set; }
    public int Provisions { get; private set; } = 3;
    public float Hull { get; private set; } = 1;
    public float Crew { get; private set; } = 1;
    public bool Collected { get; private set; }
    public bool Sorted { get; private set; }
    public bool Posted { get; private set; }
    public bool Final { get; private set; }
    public int Signatures => arrived.Skip(1).Take(4).Count(x=>x);
    public bool Ready => Public ? Signatures==4 : Posted;
    public bool Serviced => serviced[Port];
    public string Message { get; private set; } = "";
    public string Heading => Public ? "The public packet" : Mail(Island).Contents;
    public string Letter => Public ? PostLetters.PublicMail[Order.Tier-1] : Mail(Island).Letter;
    PostLetter Mail(int island)
    {
        if(Order.Articles is {} p && island==Island)
            return new($"Sailing articles for {p.Vessel}",$"To our partners aboard {p.ConsortVessel} at {p.ConsortHome}. We sail with {p.Cargo}. Look for {p.Signal} and lead us to {p.Refuge}. Leave the depth beside your signature. Signed for {p.Home} by {p.Captain}.",
                $"The charter comes back in an oilskin. Under the signature of {p.Consort} is a pencilled sounding and the message, “We have saved your berth.”");
        return Arc.Islands[island].Mail ?? PostLetters.Islands[Order.Tier-1][island];
    }
    public string Reply(int port) => Mail(port-1).Answer;
    public string Counter => Public ? $"{Signatures} of 4 seals" : Posted ? "Reply aboard" : Sorted ? "Countersealed" : Collected ? "Letter aboard" : "Awaiting pickup";
    public string Instructions => Ready ? $"The packet is ready. Muster the crew for {Order.Title}."
        : Public ? "Take the circular to all four islanders. They will add their own seals in any order."
        : !Collected ? $"Pick up the oilskin letter at {Name(Pickup)}."
        : !Sorted ? "Have the sorting hulk stamp the packet, or take the lee road and identify its recipient yourself."
        : $"Deliver to {Arc.Islands[Island].Speaker} at {Name(Island+1)}.";
    public readonly Vector2[] Chart = [new(.13f,.51f),new(.31f,.20f),new(.69f,.16f),new(.86f,.53f),new(.61f,.84f),new(.45f,.48f),new(.25f,.82f)];
    public readonly PostLane[] Lanes;
    readonly bool[] arrived=new bool[7], serviced=new bool[7];

    public PostalCircuit(CampaignOrder order,int seed,float hull=1,float crew=1)
    {
        Hull=Math.Clamp(hull,.01f,1);Crew=Math.Clamp(crew,.01f,1);
        Order=order; Arc=FarLedger.Arcs[order.Tier-1];
        Island=Array.FindIndex(Arc.Islands,island=>island.Island==order.Island);
        Pickup=Island<0?0:1+(Island+1+(order.Tier%2))%4;
        var random=new Random(seed);
        SeaDuty[] water=[SeaDuty.Convoy,SeaDuty.Hunt,SeaDuty.Salvage,SeaDuty.Sounding,SeaDuty.Blockade];
        random.Shuffle(water);
        Lanes=[new(0,1,water[0]),new(0,5,water[1]),new(0,6,water[2]),new(1,2,water[3]),
            new(2,3,water[4]),new(3,4,water[1]),new(4,6,water[3]),new(5,1,SeaDuty.Landing),
            new(5,2,water[0]),new(5,3,water[2]),new(5,4,SeaDuty.Landing),new(5,6,SeaDuty.Landing)];
        for(int i=1;i<Chart.Length;i++)Chart[i]+=new Vector2(random.NextSingle()-.5f,random.NextSingle()-.5f)*.067f;
    }
    public string Name(int port) => port switch
    {
        0 => "The post tender",5 => "Sorting hulk",6 => "Low-water office",_ => Arc.Islands[port-1].Island
    };
    public bool Visited(int port) => arrived[port];
    public IEnumerable<(int Port,SeaDuty Duty)> Routes => Lanes.Where(l=>l.From==Port || l.To==Port)
        .Select(l=>(l.From==Port?l.To:l.From,l.Duty));
    public int Goal(int port) => Ready ? 0 : Public ? port is >=1 and <=4 && !arrived[port] ? 1 : 0
        : !Collected ? (port==Pickup?1:0) : !Sorted ? (port==5||port==6?1:0) : (port==Island+1?1:0);

    public CampaignOrder? Depart(int port)
    {
        if(Destination>=0 || Final)return null;
        var lane=Routes.FirstOrDefault(l=>l.Item1==port,(-1,SeaDuty.Sounding));
        if(lane.Item1<0)return null;
        Destination=port;
        var duty=lane.Item2;
        string place=Name(port);
        string boss = new[]{"Tarred Sawbill","Reedwater Heron","Pollen Manta","Boiler Seal","Warp Eel","Copper Conch","The Bench Crab","Wandering Dogfish","Salt Ladderback","Nursery Skate","Waxbill Kite","Sleeping Prawn","Tinfin Sturgeon","Drumhead Ray","Mooring Dog","Milktooth Leviathan"}[Order.Tier-1];
        string cargo=Public?"the public packet":Collected?Mail(Island).Contents:"the post crew";
        var here=Name(Port);
        string title=duty switch
        {
            SeaDuty.Landing=>"The towpath to "+place, SeaDuty.Salvage=>"Letters in the drift",SeaDuty.Convoy=>"The packet boats",
            SeaDuty.Hunt=>"Clear the dispatch lane",SeaDuty.Blockade=>"Through the mail inspection",_=>"The pilot’s cut"
        };
        string task=duty switch
        {
            SeaDuty.Landing=>$"Cross the haul road and open the delivery wicket at {place}.",
            SeaDuty.Salvage=>$"Raise the drifting mail sacks on the way to {place}.",
            SeaDuty.Convoy=>$"Bring the post skiffs safely alongside at {place}.",
            SeaDuty.Hunt=>$"Track the beast that has been overturning boats off {place}.",
            SeaDuty.Blockade=>$"Open the sealed lane for the packet bound for {place}.",
            _=>$"Read the pilot marks to open the cut into {place}."
        };
        return new CampaignOrder(Order.Id+"-post-"+Legs,Order.Region,title,$"Nell sends {cargo} from {here} to {place}.",task,boss,
            $"The crew makes the landing at {place}.",duty,Order.Tier,2+(Order.Tier+Port+port)%3)
        { Island=port is >=1 and <=4 ? place : Order.Island, LandingSteps=duty==SeaDuty.Landing ? [
            new(LandingAction.Haul,YardSite.Fallen,"The towline","Haul the post boat off the bank"),
            new(LandingAction.Turn,YardSite.East,"Delivery wicket","Turn the handle and open the delivery wicket")
        ] : null };
    }
    public void Arrive(int silver,float health,bool ashore)
    {
        if(Destination<0)return;
        if(ashore)Crew=Math.Clamp(health,.12f,1);else Hull=Math.Clamp(health,.12f,1);
        Purse+=Math.Max(0,silver); Legs++;Port=Destination;Destination=-1;
        bool first=!arrived[Port];arrived[Port]=true;
        Message=$"Made fast at {Name(Port)}.";
        if(Public && first && Port is >=1 and <=4)
        { Message=Arc.Islands[Port-1].Speaker+" seals the register. "+Reply(Port);Purse+=4; }
        if(!Public)
        {
            if(Port==Pickup && !Collected) {Collected=true;Purse+=3;Message="Nell passes the letter across with both hands. “Read it before you put it away.”";}
            if(Collected && Port==5 && !Sorted){Sorted=true;Message="The clerk holds the letter to the lamp and stamps the oilskin. The address is yours now.";}
            if(Sorted && Port==Island+1 && !Posted){Posted=true;Purse+=8;Message=Reply(Port);}
        }
        if(first && (Port is 0 or 5 or 6))Provisions++;
    }
    public bool Address(int port)
    {
        if(Public||Port!=6||!Collected||Sorted)return false;
        Sorted=port==Island+1;
        Message=Sorted?"The low-water clerk checks the return seal. You may carry the packet straight to its recipient."
            :"The clerk shakes her head. “Read the letter again. Their work is in there somewhere.”";
        return Sorted;
    }
    public void Tend(bool repair)
    {
        if(Serviced || Provisions==0 || (repair?Hull:Crew)>=1)return;
        serviced[Port]=true;Provisions--;
        if(repair)Hull=Math.Min(1,Hull+.42f);else Crew=Math.Min(1,Crew+.48f);
        Message=repair?"Vara caulks the working seams and checks every pin against her thumb.":"Lio spreads supper out on the floorboards. Everyone gets a dry watch below.";
    }
    public bool Muster()
    {
        if(!Ready||Final||Destination>=0)return false;
        Final=true;return true;
    }
}
