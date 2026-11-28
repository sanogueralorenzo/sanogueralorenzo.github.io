using BoatsNBeasts.Core;
using Godot;
using static BoatsNBeasts.HarborType;

namespace BoatsNBeasts;

public partial class FlotillaWatch : CrewRun
{
    public CampaignOrder Order {get;set;}=FreeFleet.CinderCharter();
    public FlotillaPassage Passage {get;private set;}=null!;
    public CrewRun? Child {get;private set;}
    public override CrewRun? ActiveWatch=>Child;
    public override int SilverEarned=>Passage==null?0:Passage.Purse+(Child?.SilverEarned??0);
    public override bool AskShipmate(Shipmate mate)=>Child?.AskShipmate(mate)==true;
    CanvasLayer? board;
    VBoxContainer copy=null!;
    bool settling;
    public override void _Ready(){Passage=new(Order,Seed);Council();}
    void Council()
    {
        if(board!=null){RemoveChild(board);board.QueueFree();}
        board=new();AddChild(board);
        var water=new ColorRect{Color=new("132f39")};board.AddChild(water);water.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var frame=new MarginContainer();water.AddChild(frame);frame.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        foreach(string edge in new[]{"top","bottom","left","right"})frame.AddThemeConstantOverride("margin_"+edge,32);
        var body=new VBoxContainer();body.AddThemeConstantOverride("separation",8);frame.AddChild(body);
        body.AddChild(Text("THE FREE FLEET    /    "+Order.Region.ToUpperInvariant(),17,Teal));
        body.AddChild(Text(Order.Title,39,Brass,true));
        var row=new HBoxContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};row.AddThemeConstantOverride("separation",30);body.AddChild(row);
        var chart=new FleetStandards{Passage=Passage,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,SizeFlagsStretchRatio=.93f};
        row.AddChild(chart);
        var paper=new ScrollContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,HorizontalScrollMode=ScrollContainer.ScrollMode.Disabled};
        row.AddChild(paper);copy=new(){SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};copy.AddThemeConstantOverride("separation",12);paper.AddChild(copy);
        string state=$"Hull {Passage.Hull:P0}   ·   Crew {Passage.Crew:P0}   ·   {Passage.Supplies} provisions   ·   {SilverAboard} silver aboard";
        body.AddChild(Text(state,19,Cream));
        if(!Passage.Pledge.HasValue){Articles();return;}
        if(Passage.Won)
        {
            Line("THE REFUGE ANSWERS",17,Teal);Line(Passage.Papers.Refuge,31,Brass,true);Line(Passage.Arrival);
            Action("Return with the company",()=>Finish(true),true);return;
        }
        Line($"WATCH {Passage.Stage+1} OF 6",16,Teal);Line(Passage.Station,31,Brass,true);
        if(Passage.Arrival.Length>0)Line(Passage.Arrival,19,Teal);
        var options=Passage.Options();
        for(int n=0;n<options.Length;n++)
        {
            int index=n;Line(options[n].Brief,19,Cream);Action(options[n].Label,()=>CastOff(index),n==0);
        }
        if(Passage.Supplies>0 && Passage.Hull<.995f)Action("Caulk the ships   ·   1 provision",()=>{Passage.Tend(true);Council();});
        if(Passage.Supplies>0 && Passage.Crew<.995f)Action("Feed the yards   ·   1 provision",()=>{Passage.Tend(false);Council();});
    }
    void Articles()
    {
        var p=Passage.Papers;
        Line("AT THE CAPTAINS’ TABLE",16,Teal);Line("Who gets the first berth?",31,Brass,true);
        Line(Order.Brief);Line($"{p.Vessel} sails with {p.Captain}. {p.ConsortVessel} sails with {p.Consort}. Their pact lasts all six watches.",19,Teal);
        Line("Give the first berth to the people ashore. They pack one extra provision and tend the landing parties between watches.",18,Cream);
        Action("Promise the shore a place",()=>{Passage.Sign(true);Council();},true);
        Line("Give the pilots a working berth. Their carpenters patch the hulls after each watch at sea.",18,Cream);
        Action("Promise the pilots a berth",()=>{Passage.Sign(false);Council();});
    }
    void Line(string words,int size=22,Color? color=null,bool title=false)=>copy.AddChild(Text(words,size,color??Cream,title));
    void Action(string name,Action go,bool primary=false)
    {
        var b=Button(name,go,primary);copy.AddChild(b);if(primary)b.GrabFocus();
    }
    void CastOff(int index)
    {
        if(Child!=null||settling||Passage.Depart(index) is not {} leg)return;
        if(board!=null){RemoveChild(board);board.QueueFree();board=null;}
        var o=leg.Order;
        Child=leg.Duty switch
        {
            FleetDuty.Command=>new FlotillaCommand{Order=o,StartingCondition=Passage.Hull},
            FleetDuty.Muster=>new MusterLanding{Order=o,StartingCondition=Passage.Crew},
            FleetDuty.Privateer=>new PrizeWatch{Order=o},FleetDuty.Underways=>new UnderwaysExpedition{Order=o,StartingCondition=Passage.Crew},
            FleetDuty.Packet=>new NightPostWatch{Order=o,StartingHull=Passage.Hull,StartingCrew=Passage.Crew},
            FleetDuty.Crossing=>new BluewaterVoyage{Order=o},
            _=>new KilnExpedition{Order=o}
        };
        Child.Seed=leg.Seed;Child.Stores=Stores;Child.Outfit=Outfit;Child.Vessel=Vessel;Child.Figurehead=Figurehead;
        Child.CarriedSilver=CarriedSilver+Passage.Purse;Child.LandingName=Passage.Papers.Refuge;Child.Returned=Arrive;AddChild(Child);
        if(Child is PrizeWatch prize)prize.Watch.Ship.Health=prize.Watch.Ship.MaxHealth*Passage.Hull;
        if(Child is BluewaterVoyage blue)blue.Course.Ship.Health=blue.Course.Ship.MaxHealth*Passage.Hull;
        if(Child is KilnExpedition shore)shore.Yard.ArriveByPost(Passage.Crew);
    }
    void Arrive(bool won,int earned)
    {
        if(settling || Child==null)return;
        settling=true;var child=Child;
        float condition=child switch{
            FlotillaCommand sea=>sea.Condition,MusterLanding land=>land.Condition,PrizeWatch watch=>watch.Watch.HealthFraction,
            UnderwaysExpedition under=>(float)under.Crawl.Vitality/under.Crawl.Maximum,
            BluewaterVoyage blue=>blue.Course.Ship.Health/blue.Course.Ship.MaxHealth,
            KilnExpedition foot=>(float)foot.Yard.Health/foot.Yard.MaximumHealth,NightPostWatch post=>post.HullCondition,_=>1};
        Child=null;Passage.Arrive(won,earned,condition,(child as NightPostWatch)?.CrewCondition);
        Callable.From(()=>{
            if(!IsInsideTree())return;
            RemoveChild(child);child.QueueFree();settling=false;
            if(!won){Finish(false);return;}
            Council();
        }).CallDeferred();
    }
    void Finish(bool won)
    {
        if(settling)return;settling=true;
        if(Returned!=null)Returned(won,Passage.Purse);
        else GetTree().ChangeSceneToFile("res://main.tscn");
    }
}
