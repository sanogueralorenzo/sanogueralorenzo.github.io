using BoatsNBeasts.Core;
using Godot;
using static BoatsNBeasts.HarborType;

namespace BoatsNBeasts;

public partial class NightPostWatch : CrewRun
{
    public CampaignOrder Order { get; set; }=FarLedger.Arcs[0].Islands[0].Outings.First(o=>o.Postal);
    public override bool AskShipmate(Shipmate mate) => inTransit && stage?.AskShipmate(mate)==true;
    public override int SilverEarned => watch.Purse+(stage?.SilverEarned??0);
    PostalCircuit watch=null!;
    CrewRun? stage;
    internal CrewRun? OnDeck=>stage;
    public override CrewRun? ActiveWatch=>stage;
    public float StartingHull {get;set;}=1;
    public float StartingCrew {get;set;}=1;
    public float HullCondition=>stage is BluewaterVoyage sea?sea.Course.Ship.Health/sea.Course.Ship.MaxHealth:watch.Hull;
    public float CrewCondition=>stage is KilnExpedition foot?(float)foot.Yard.Health/foot.Yard.MaximumHealth:watch.Crew;
    CanvasLayer? desk;
    VBoxContainer copy=null!;
    PostMap map=null!;
    bool inTransit;
    public override void _Ready()
    {
        watch=new(Order,Seed,StartingHull,StartingCrew);
        Desk();
    }
    void Desk()
    {
        if(desk!=null){RemoveChild(desk);desk.QueueFree();}
        desk=new();AddChild(desk);
        var back=new ColorRect{Color=new("122d39")};desk.AddChild(back);back.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var margin=new MarginContainer();back.AddChild(margin);margin.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        foreach(var side in new[]{"left","right","top","bottom"})margin.AddThemeConstantOverride("margin_"+side,28);
        var body=new VBoxContainer();body.AddThemeConstantOverride("separation",11);margin.AddChild(body);
        body.AddChild(Text("THE NIGHT POST    /    "+Order.Region.ToUpperInvariant(),18,Teal));
        body.AddChild(Text(Order.Island.Length>0 ? Order.Island : Order.Title,39,Cream,true));
        var row=new HBoxContainer{SizeFlagsVertical=Control.SizeFlags.ExpandFill};row.AddThemeConstantOverride("separation",26);body.AddChild(row);
        map=new PostMap{Watch=watch,Select=Select,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,SizeFlagsStretchRatio=1.24f};row.AddChild(map);
        var scroll=new ScrollContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,HorizontalScrollMode=ScrollContainer.ScrollMode.Disabled};
        row.AddChild(scroll);
        var outer=new MarginContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};outer.AddThemeConstantOverride("margin_right",7);scroll.AddChild(outer);
        copy=new VBoxContainer{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};copy.AddThemeConstantOverride("separation",8);outer.AddChild(copy);
        body.AddChild(Text($"Hull {watch.Hull:P0}    ·    Crew {watch.Crew:P0}    ·    {watch.Provisions} provisions    ·    {SilverAboard} silver aboard    ·    Escape to anchor",18,Teal));
        AtPort();
    }
    void Clear()
    {
        foreach(var node in copy.GetChildren()){copy.RemoveChild(node);node.QueueFree();}
        map.Selected=-1;map.QueueRedraw();
    }
    void AddButton(string name,Action action,bool primary=false)
    {
        var button=Button(name,action,primary);copy.AddChild(button);
        if(!copy.GetChildren().OfType<Button>().Skip(1).Any())button.GrabFocus();
    }
    void AtPort()
    {
        Clear();
        copy.AddChild(Text("ALONGSIDE    /    "+watch.Counter.ToUpperInvariant(),16,Teal));
        copy.AddChild(Text(watch.Name(watch.Port),32,Brass,true));
        if(watch.Message.Length>0)copy.AddChild(Text(watch.Message,20,Cream));
        copy.AddChild(Text(watch.Instructions,21,Cream));
        if(watch.Ready)AddButton("Muster for "+Order.Title,()=>{if(watch.Muster())Launch(Order);},true);
        if(!watch.Public && watch.Port==6 && watch.Collected && !watch.Sorted)AddButton("Address the packet",Address);
        if((watch.Collected || watch.Public)&&!watch.Ready)AddButton("Unfold the letter",Letter);
        foreach(var route in watch.Routes)AddButton(watch.Name(route.Port)+"   ›",()=>Select(route.Port));
        if(!watch.Serviced && watch.Provisions>0)
        {
            if(watch.Hull<.995f)AddButton("Caulk the hull   ·   1 provision",()=>{watch.Tend(true);Desk();});
            if(watch.Crew<.995f)AddButton("Feed the crew   ·   1 provision",()=>{watch.Tend(false);Desk();});
        }
    }
    void Letter()
    {
        Clear();copy.AddChild(Text("INSIDE THE OILSKIN",16,Teal));copy.AddChild(Text(watch.Heading,30,Brass,true));
        copy.AddChild(Text(watch.Letter,23,Cream,true));AddButton("Fold it away",AtPort,true);
    }
    void Address()
    {
        Clear();copy.AddChild(Text("THE LOW-WATER OFFICE",16,Teal));copy.AddChild(Text("Who will take the packet?",29,Brass,true));
        copy.AddChild(Text(watch.Letter,21,Cream,true));
        for(int i=0;i<watch.Arc.Islands.Length;i++){int port=i+1;AddButton(watch.Arc.Islands[i].Speaker,()=>{watch.Address(port);AtPort();});}
        AddButton("Return to the deck",AtPort);
    }
    internal static string Lane(SeaDuty duty)=>duty switch
    {
        SeaDuty.Landing=>"Towpath ashore",SeaDuty.Convoy=>"Packet convoy",SeaDuty.Salvage=>"Drift salvage",SeaDuty.Hunt=>"Beast patrol",
        SeaDuty.Blockade=>"Examination chain",_=>"Unmarked cut"
    };
    void Select(int port)
    {
        if(inTransit)return;
        if(port==watch.Port){AtPort();return;}
        var lane=watch.Routes.FirstOrDefault(r=>r.Item1==port,(-1,SeaDuty.Sounding));
        Clear();map.Selected=port;map.QueueRedraw();
        copy.AddChild(Text(watch.Name(port),31,Brass,true));
        if(port is >=1 and <=4)copy.AddChild(Text(watch.Arc.Islands[port-1].Speaker,20,Teal));
        if(lane.Item1>=0)
        {
            var duty=lane.Item2;
            copy.AddChild(Text(Lane(duty).ToUpperInvariant(),16,Teal));
            string detail=duty switch
            {
                SeaDuty.Landing=>"Take Lio ashore to haul the post boat through the towpath. The landing party carries its current wounds.",
                SeaDuty.Convoy=>"Meet the small packet boats offshore. Keep the mail fleet together under fire.",
                SeaDuty.Salvage=>"The outer bags have come loose. Work with the deck crew to recover them before entering port.",
                SeaDuty.Hunt=>"Hunt the beast working the mail lane. The bow watch has already found its feeding grounds.",
                SeaDuty.Blockade=>"Run the inspection line. Grapple the examination buoys and fire through the chain.",
                _=>"Follow the sounding marks through the reef. Work the cutter round each pilot station."
            };
            copy.AddChild(Text(detail,22,Cream));
            AddButton(duty==SeaDuty.Landing?"Walk the towpath":"Take the crossing",()=>{if(watch.Depart(port) is { } leg)Launch(leg);},true);
        }
        else copy.AddChild(Text("No direct passage from here. Follow the marked lanes to a neighboring port.",22,Cream));
        AddButton("Back to "+watch.Name(watch.Port),AtPort);
    }
    void Launch(CampaignOrder leg)
    {
        if(inTransit)return;
        inTransit=true;
        if(desk!=null){RemoveChild(desk);desk.QueueFree();desk=null;}
        stage=leg.Ashore ? new KilnExpedition{Order=leg} : new BluewaterVoyage{Order=leg};
        stage.Seed=unchecked(Seed+watch.Legs*7919+(watch.Final?9929:31));stage.Stores=Stores;stage.Outfit=Outfit;
        stage.Vessel=Vessel;stage.Figurehead=Figurehead;
        stage.CarriedSilver=CarriedSilver+watch.Purse;stage.LandingName=watch.Final?LandingName:watch.Name(watch.Destination);
        stage.Returned=Arrive;AddChild(stage);
        if(stage is KilnExpedition landing)landing.Yard.ArriveByPost(watch.Crew);
        if(stage is BluewaterVoyage crossing)crossing.Course.Ship.Health=crossing.Course.Ship.MaxHealth*watch.Hull;
    }
    void Arrive(bool won,int silver)
    {
        if(!inTransit || stage==null)return;
        inTransit=false;
        if(!won||watch.Final)
        {
            if(Returned!=null)Returned(won,watch.Purse+silver);
            else GetTree().ChangeSceneToFile("res://main.tscn");
            return;
        }
        bool ashore=stage is KilnExpedition;
        float health=stage switch {
            KilnExpedition foot=>(float)foot.Yard.Health/foot.Yard.MaximumHealth,
            BluewaterVoyage sea=>sea.Course.Ship.Health/sea.Course.Ship.MaxHealth,_=>1 };
        var previous=stage;stage=null;watch.Arrive(silver,health,ashore);
        Callable.From(()=>{RemoveChild(previous);previous.QueueFree();Desk();}).CallDeferred();
    }
}
