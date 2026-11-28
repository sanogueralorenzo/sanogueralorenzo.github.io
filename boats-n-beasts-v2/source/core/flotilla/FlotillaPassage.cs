namespace BoatsNBeasts.Core;

public enum FleetDuty { Command, Muster, Privateer, Underways, Crossing, Landing, Packet }
public sealed record FleetStage(FleetDuty Duty,CampaignOrder Order,int Seed);
public sealed record FleetOption(string Label,string Brief,FleetDuty Duty);
public sealed class FlotillaPassage
{
    public CampaignOrder Order {get;}
    public FleetArticles Papers=>Order.Articles!;
    public int Seed {get;}
    public int Stage {get;private set;}
    public int Purse {get;private set;}
    public int Supplies {get;private set;}=3;
    public float Hull {get;private set;}=1;
    public float Crew {get;private set;}=1;
    public bool? Pledge {get;private set;}
    public FleetStage? Underway {get;private set;}
    public bool Won=>Stage==6;
    public bool Lost {get;private set;}
    public string Arrival {get;private set;}="";
    bool musteredAshore;
    public bool OnFoot(FleetDuty duty)=>duty is FleetDuty.Muster or FleetDuty.Underways or FleetDuty.Landing;
    public FlotillaPassage(CampaignOrder order,int seed){Order=order;Seed=seed;}
    public string Station=>Stage switch{0=>"Call the company",1=>"Establish the claim",2=>"Load for the passage",
        3=>"Carry the dispatch",4=>"Break the cordon",5=>"Bring the fleet in",_=>"Make fast at Last Light"};
    public void Sign(bool peopleFirst)
    {
        if(Pledge.HasValue)return;
        Pledge=peopleFirst;
        if(peopleFirst)Supplies++;
    }
    public bool Tend(bool hull)
    {
        if(Underway!=null||Lost||Won||Supplies<=0||(hull?Hull:Crew)>=1)return false;
        if(hull)Hull=Math.Min(1,Hull+.42f);else Crew=Math.Min(1,Crew+.44f);
        Supplies--;return true;
    }
    public FleetOption[] Options()
    {
        var p=Papers;
        FleetOption Go(string name,string work,FleetDuty duty)=>new(name,work,duty);
        return Stage switch
        {
            0=>[Go("Raise the harbor crews",$"Call {p.Captain} to the yard. Get the boats through the tide gate at {p.Home}.",FleetDuty.Muster),
                Go("Rendezvous offshore",$"Take the cutter out to meet {p.Vessel} and {p.ConsortVessel}. Bring the signal boat within hailing distance of {p.Home}.",FleetDuty.Command)],
            1=>[Go("Follow the receiving ships",$"Aboard the collectors’ fleet are the papers for {p.Cargo}. Identify the receiver by this signal — {p.Signal}.",FleetDuty.Privateer),
                Go("Recover the yard record",$"The old service lifts at {p.ConsortHome} still lead to the original freight docket. Find its witnesses and bring back the marked entry.",FleetDuty.Underways)],
            2=>[Go("Rig the cargo at sea",$"Recover {p.Cargo} at the outer cranes and escort the loaded carrier to {p.ConsortHome}.",FleetDuty.Crossing),
                Go("Take the shore tackle",$"Work across the landing districts. Pass {p.Cargo} from the yard to the hands of {p.Consort}.",FleetDuty.Landing)],
            3=>[Go("Put the pact in the island post",$"Carry the island packet and its counterseal. The pilot at {p.Refuge} needs to know which vessels the fleet promised to take.",FleetDuty.Packet),
                Go("Carry the pilot out yourself",$"The fourth island has lost its pilot boat. Meet its crew and get them through the examination chain to {p.Refuge}.",FleetDuty.Crossing)],
            4 when musteredAshore=>[Go("Command the ships through",$"The yard crews raised {p.Vessel}. Now take station with her on the water. Break {Order.Boss}’s cordon and recover those caught outside.",FleetDuty.Command)],
            4=>[Go("Take the landing party in",$"The escort ships are holding off {Order.Boss}. Bring their tenders through the shore yards and clear the gate at {p.Refuge}.",FleetDuty.Muster)],
            5=>[Go("Ride the last convoy",$"{Order.Boss} has fallen back on the outer anchorage. Sail with the last boats, give the agreed signal and escort the fleet through.",FleetDuty.Command),
                Go("Stand the final shore watch",$"Hold {p.Refuge} against the last landing. With {p.Captain}, work the refuge gate and send the company's last boats inside.",FleetDuty.Muster)],
            _=>[]
        };
    }
    public FleetStage? Depart(int choice)
    {
        if(!Pledge.HasValue||Underway!=null||Lost||Won)return null;
        var options=Options();if(choice<0||choice>=options.Length)return null;
        var o=options[choice];var p=Papers;var kind=o.Duty;bool foot=OnFoot(kind);
        int legs=kind switch {FleetDuty.Command or FleetDuty.Muster=>Stage==0?2:3,FleetDuty.Privateer or FleetDuty.Underways=>5,
            FleetDuty.Packet=>5,FleetDuty.Crossing when Stage==3=>8,_=>6};
        var duty=foot?SeaDuty.Landing:kind==FleetDuty.Privateer?SeaDuty.Hunt:kind==FleetDuty.Crossing
            ? Stage==3?SeaDuty.Blockade:SeaDuty.Salvage:SeaDuty.Convoy;
        var order=new CampaignOrder($"{Order.Id}-watch-{Stage}-{choice}",Order.Region,o.Label,o.Brief,
            o.Brief,Order.Boss,Report(Stage),duty,Order.Tier,legs)
            {Island=Stage==3?p.ConsortHome:p.Home,Articles=p,Postal=kind==FleetDuty.Packet,PrizeWatch=kind==FleetDuty.Privateer,
                Underways=kind==FleetDuty.Underways,Evidence=new(p.Cargo,p.Signal,$"The tally for {p.Cargo} bears the mark from {p.Home}. Under it a second hand has written the name of the refuge.")};
        if(Stage==0)musteredAshore=kind==FleetDuty.Muster;
        return Underway=new(kind,order,unchecked(Seed+Stage*8101+choice*1297));
    }
    public void Arrive(bool won,int earned,float condition,float? packetCrew=null)
    {
        if(Underway==null||Lost||Won)return;
        var trip=Underway;Underway=null;Purse=checked(Purse+Math.Max(0,earned));
        if(!won){Lost=true;return;}
        condition=Math.Clamp(condition,0,1);
        if(OnFoot(trip.Duty))Crew=Math.Clamp(condition+(Pledge==true?.10f:0),.29f,1);
        else Hull=Math.Clamp(condition+(Pledge==false?.18f:0),.29f,1);
        if(trip.Duty==FleetDuty.Packet && packetCrew.HasValue)Crew=Math.Clamp(packetCrew.Value,.29f,1);
        if(Stage==1)Supplies++;
        Arrival=Report(Stage);Stage++;
    }
    string Report(int stage)
    {
        var p=Papers;
        return stage switch{
            0=>$"The company colors go up aboard {p.Vessel}. {p.ConsortVessel} answers from the other pier.",
            1=>$"The marked docket is in the cabin. The witnesses recognize {p.Signal}.",
            2=>$"{p.Cargo} is aboard. The receipt comes from {p.Consort}.",
            3=>$"The refuge has answered. The outer pilots are waiting at {p.Refuge}.",
            4=>$"{Order.Boss} has lost the cordon. The two crews count their boats before the final watch.",
            _=>Pledge==true?p.Pledge:p.Berth};
    }
}
