using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class PilotageVoyage : CrewRun
{
    public CampaignOrder Order { get; set; } = FarLedger.Arcs[0].Islands[0].Outings[0];
    public override bool AskShipmate(Shipmate mate) => !ChartOpen && !Sights.Won && Sights.Ship.CallShipmate(mate);
    public override int SilverEarned => Sights?.Silver ?? 0;
    internal PilotSoundings Sights { get; private set; } = null!;
    internal OceanView3D Ocean { get; private set; } = null!;
    internal bool ChartOpen {get;private set;} = true;
    PilotPlot plot = null!;
    Node3D tender=null!, buoy=null!;
    bool leaving;

    public override void _Ready()
    {
        Sights=new(Order,Seed,Stores,Outfit,Vessel);
        var country=SeaCountry.At(Order.Region,Order.Island);
        Ocean=new(){Figurehead=Figurehead,Voyage=Sights.Ship,CustomPlace=p=>BluewaterCoast.Build(p,country,false)};
        AddChild(Ocean);Ocean.PaintWater(BluewaterCoast.Water(country.Climate));Ocean.OpenChart();
        foreach(var light in Sights.Lights)
        {
            var beacon=Light(light,country);
            beacon.Position=NativeStage3D.Point(light.Position);
            Ocean.AddChild(beacon);
        }
        tender=BluewaterArt.Prop(country,"port");tender.Position=NativeStage3D.Point(Sights.Landing);Ocean.AddChild(tender);
        buoy=BluewaterArt.Prop(country,"buoy");Ocean.AddChild(buoy);
        var layer=new CanvasLayer();AddChild(layer);
        plot=new(){Trip=this,MouseFilter=Control.MouseFilterEnum.Stop};layer.AddChild(plot);
        plot.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        Ocean.Advance(.016f); Sync();
    }
    static Node3D Light(SurveyLight light,SeaCountry country)
    {
        var mark=new ActorGeometry();
        var dye=new Color(country.Accent);
        mark.Sphere(new(0,.04f,0),new(.64f,.15f,.62f),new("664c47"),10,5);
        mark.Ring(new(0,.17f,0),.44f,.03f,new("e3c796"));
        float h=.95f+(light.Shape%3)*.25f;
        mark.Tube([new(0,.14f,0),new(0,h,0)], [.14f,.075f],dye,7);
        for(int i=0;i<1+light.Shape%3;i++)mark.Ring(new(0,.40f+i*.16f,0),.13f,.029f,new("f5dea7"));
        if(light.Shape<4)
        {
            mark.Tube([new(-.29f,h,0),new(.29f,h,0)],.035f,new("b38b55"),6);
            mark.Polygon([new(-.21f,h,0),new(-.21f,h-.30f,0),new(.15f,h-.19f,0)],new("e27650"),Vector3.Back);
        }
        else mark.Sphere(new(0,h,0),new(.18f,.22f,.18f),new("fff0a2"),6,4);
        var root=new Node3D();root.AddChild(new MeshInstance3D{Mesh=mark.Mesh(DioramaSurface.Material)});return root;
    }
    internal void ToggleChart()
    {
        if(Sights.Lost || Sights.Won || Sights.Ship.Mode==VoyageMode.Upgrade)return;
        ChartOpen=!ChartOpen;plot.QueueRedraw();
    }
    internal void ResumeSailing() {ChartOpen=false;plot.QueueRedraw();}
    static bool Held(Key a,Key b)=>Input.IsPhysicalKeyPressed(a)||Input.IsPhysicalKeyPressed(b);
    public override void _PhysicsProcess(double delta)
    {
        if(leaving)return;
        if(!ChartOpen && Sights.Ship.Mode==VoyageMode.Sailing && !Sights.Won)
        {
            var ship=Sights.Ship;
            V2 movement=new((Held(Key.D,Key.Right)?1:0)-(Held(Key.A,Key.Left)?1:0),(Held(Key.S,Key.Down)?1:0)-(Held(Key.W,Key.Up)?1:0));
            var enemy=ship.Enemies.Where(e=>e.Health>0).MinBy(e=>V2.DistanceSquared(e.Position,ship.Position));
            Sights.Tick((float)delta,new(movement,Input.IsPhysicalKeyPressed(Key.Shift),Input.IsPhysicalKeyPressed(Key.Space),enemy?.Position));
            foreach(var ev in ship.Events)Ocean.Effect(ev);
            ship.Events.Clear();
            Ocean.Advance((float)delta);
        }
        Sync();
    }
    void Sync()
    {
        tender.Visible=Sights.Surveyed;
        buoy.Visible=Sights.Pin.HasValue && !Sights.Surveyed;
        if(Sights.Pin is { } pin)buoy.Position=NativeStage3D.Point(pin);
        plot.QueueRedraw();
    }
    internal void Settle()
    {
        if(leaving || !(Sights.Won || Sights.Lost)) return;
        leaving=true;
        if(Returned!=null)Returned(Sights.Won,Sights.Silver);else GetTree().ChangeSceneToFile("res://main.tscn");
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(input is not InputEventKey{Pressed:true,Echo:false} e)return;
        var key=e.PhysicalKeycode==Key.None?e.Keycode:e.PhysicalKeycode;
        if((Sights.Lost||Sights.Won)&&key==Key.Enter)Settle();
        else if(Sights.Ship.Mode==VoyageMode.Upgrade)
        {
            int n=(int)key-(int)Key.Key1;
            if(n>=0 && n<Sights.Ship.UpgradeChoices.Count)Sights.Ship.Upgrade(Sights.Ship.UpgradeChoices[n]);
            else if(key==Key.Enter)Sights.Ship.TakeUpgradeHeal();else return;
        }
        else if(key is Key.M or Key.Tab)ToggleChart();
        else if(ChartOpen) {if(!plot.ChartKey(key))return;}
        else if(key==Key.E)Sights.Sound();
        else if(key==Key.Q)Sights.Hail();
        else if(key==Key.R)Sights.Patch();
        else return;
        GetViewport().SetInputAsHandled();
    }
}
