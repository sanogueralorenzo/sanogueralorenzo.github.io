using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class BluewaterVoyage : CrewRun
{
    public CampaignOrder Order { get; set; } = FarLedger.Arcs[0].Orders[0];
    public override bool AskShipmate(Shipmate mate) => !InMenu && Course.Ship.CallShipmate(mate);
    public override int SilverEarned => Course?.Purse ?? 0;
    internal BluewaterCourse Course { get; private set; } = null!;
    internal OceanView3D Sea { get; private set; } = null!;
    internal bool InMenu => Course.Phase is ChartPhase.Passage or ChartPhase.Refit or ChartPhase.Lost or ChartPhase.Won || Course.Ship.Mode == VoyageMode.Upgrade;
    BluewaterHud hud = null!;
    CanvasLayer canvas = null!;
    Control? modal;
    Node3D? station, support;
    string supportHull="";
    Node3D mooring = null!, destination = null!, lee = null!, localFloat = null!;
    readonly Dictionary<FleetBoat,Node3D> fleet = [];
    readonly List<Action> options = [];
    readonly List<Node3D> banks=[];
    int laneRevision=-1;
    AudioStreamPlayer bell = null!;
    string shown = "", propKind = "", coast = "";
    bool hook, patch, done;
    float clock;

    public override void _Ready()
    {
        Course = new(Order, Seed, Stores, Outfit, Vessel);
        Sea = new() { Name = "Ocean", Figurehead=Figurehead,Voyage = Course.Ship };
        Sea.CustomActor = enemy => enemy == Course.Captain ? BluewaterArt.Commander(Order,Course.Country) : enemy == Course.Picket ? BluewaterArt.Prop(Course.Country,"picket") : null;
        Sea.CustomPlace=place=>BluewaterCoast.Build(place,Course.Country,place.Id==Course.DepartureId);
        AddChild(Sea);
        Sea.PaintWater(BluewaterCoast.Water(Course.Country.Climate));
        Sea.OpenChart();
        mooring = BluewaterArt.Prop(Course.Country,"refuge");
        mooring.Name = "FriendlyMooring"; Sea.AddChild(mooring);
        coast=Course.Region;
        lee = BluewaterArt.Prop(Course.Country,"gate");
        lee.Name="ShelterGate";Sea.AddChild(lee);
        localFloat=SeaLandmarks.Float(Course.Country);
        localFloat.Name="RegionalFloat";Sea.AddChild(localFloat);
        destination = new() {Name = "PilotMark"}; Sea.AddChild(destination);
        canvas = new(); AddChild(canvas);
        hud = new() {Scene=this, MouseFilter = Control.MouseFilterEnum.Ignore}; canvas.AddChild(hud);
        hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        bell = new() {Stream=QuayTone.Note(64,true),VolumeDb=-15}; AddChild(bell);
        Sea.Advance(.016f);
        Render();
    }

    public override void _PhysicsProcess(double delta)
    {
        if(done) return;
        float dt=(float)delta;
        if (!InMenu)
        {
            static bool Down(Key a, Key b) => Input.IsPhysicalKeyPressed(a) || Input.IsPhysicalKeyPressed(b);
            V2 move=new((Down(Key.D,Key.Right)?1:0)-(Down(Key.A,Key.Left)?1:0), (Down(Key.S,Key.Down)?1:0)-(Down(Key.W,Key.Up)?1:0));
            bool clicked=Input.IsMouseButtonPressed(MouseButton.Left);
            bool fire=clicked || Input.IsPhysicalKeyPressed(Key.Space);
            var aim=clicked ? Sea.WorldPoint(GetViewport().GetMousePosition()) : Course.AutomaticAim();
            var leg=Course.Phase; int stop=Course.Station, coins=Course.Purse;
            Course.Tick(dt,new(move,Input.IsPhysicalKeyPressed(Key.Shift),fire,aim),hook,patch);
            if(leg!=Course.Phase || stop!=Course.Station || coins!=Course.Purse && Course.HookTime>0) bell.Play();
            foreach(var effect in Course.Ship.Events) Sea.Effect(effect);
            Course.Ship.Events.Clear();
            Sea.Advance(dt);
            clock+=dt;
        }
        hook=patch=false;
        Render();
    }

    public override void _Input(InputEvent input)
    {
        if (!done && InMenu && input is InputEventKey {PhysicalKeycode:Key.Space}) GetViewport().SetInputAsHandled();
    }

    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(done || input is not InputEventKey {Pressed:true,Echo:false} k) return;
        var key = k.PhysicalKeycode is Key.None ? k.Keycode : k.PhysicalKeycode;
        var viewport = GetViewport();
        if (InMenu)
        {
            int selected=key switch {Key.Key1 or Key.Kp1=>0,Key.Key2 or Key.Kp2=>1,Key.Key3 or Key.Kp3=>2,_=>-1};
            if(selected<0 || selected>=options.Count) return;
            options[selected]();
        }
        else if(key==Key.Q) hook=true;
        else if(key==Key.E) patch=true;
        else if(key==Key.R) Course.ChangeStation();
        else return;
        viewport.SetInputAsHandled();
    }

    void Render()
    {
        var state=$"{Course.Phase}:{Course.Leg}:{Course.Ship.Mode}:{Course.Ship.PendingUpgrades}";
        if(state!=shown)
        {
            shown=state;
            if(modal!=null) {canvas.RemoveChild(modal);modal.QueueFree();modal=null;}
            options.Clear();
            if(InMenu) OpenMenu();
        }
        if(coast!=Course.Region)
        {
            coast=Course.Region;
            Sea.PaintWater(BluewaterCoast.Water(Course.Country.Climate));
            mooring.QueueFree();lee.QueueFree();localFloat.QueueFree();
            mooring=BluewaterArt.Prop(Course.Country,"refuge");Sea.AddChild(mooring);
            lee=BluewaterArt.Prop(Course.Country,"gate");Sea.AddChild(lee);
            localFloat=SeaLandmarks.Float(Course.Country);Sea.AddChild(localFloat);
            propKind="";
        }
        string kind=Course.Phase switch
        {
            ChartPhase.Port or ChartPhase.Won=>"port",
            ChartPhase.Boss=>Course.BossCovered ? Order.Duty==SeaDuty.Blockade?"chain":"buoy" : "",
            _=>Course.Job switch
            {
                SeaJob.Tow=>"convoy",SeaJob.Cut=>"chain",SeaJob.Guide=>"gate",SeaJob.Salvage=>"wreck",
                SeaJob.Unload=>"refuge",SeaJob.Track or SeaJob.Sound=>"buoy",SeaJob.DriveOff=>"prize",_=>"relay"
            }
        };
        if(Course.Field!=0)kind=Course.Field==3&&Course.FlagshipHull>0?"chain":"gate";
        if(kind!=propKind)
        {
            if(station!=null) {station.QueueFree();station=null;}
            if(kind!="") {station=BluewaterArt.Prop(Course.Country,kind);Sea.AddChild(station);}
            propKind=kind;
        }
        if(station!=null)
        {
            station.Visible=!InMenu;
            station.Position=NativeStage3D.Point(Course.Field==3&&Course.FlagshipHull>0?Course.Battery:Course.Phase==ChartPhase.Boss?Course.ShieldPoint:Course.Target,MathF.Sin(clock*1.7f)*.024f);
        }
        lee.Visible=Course.Crossing;
        if(lee.Visible)lee.Position=NativeStage3D.Point(Course.Shelter);
        localFloat.Visible=Course.Phase is ChartPhase.Running or ChartPhase.Boss;
        if(localFloat.Visible)localFloat.Position=NativeStage3D.Point(Course.Crossing?Course.Prize:Course.Weather.Center);
        mooring.Visible=Course.Phase==ChartPhase.Running&&!Course.Docked;
        mooring.Position=NativeStage3D.Point(Course.Mooring);
        destination.Position=NativeStage3D.Point(Course.Destination);
        if(laneRevision!=Course.ChannelRevision)
        {
            foreach(var old in banks)old.QueueFree();
            banks.Clear();
            foreach(var bank in Course.Banks)
            {
                var scenery=ChannelScenery.Make(Course.Country,bank);
                Sea.AddChild(scenery);banks.Add(scenery);
            }
            laneRevision=Course.ChannelRevision;
        }
        for(int i=0;i<banks.Count;i++)
        {
            banks[i].Visible=Course.Phase==ChartPhase.Running && !Course.Banks[i].Broken;
            banks[i].Position=NativeStage3D.Point(Course.Banks[i].Position);
        }
        if(Course.Field!=0 && Course.Tender is { } escort)
        {
            string shape=Course.GunPrize?"prize":"convoy";
            if(support==null || supportHull!=shape)
            {
                support?.QueueFree();
                support=BluewaterArt.Prop(Course.Country,shape);Sea.AddChild(support);
                supportHull=shape;
            }
            support.Visible=escort.Health>0;
            support.Position=NativeStage3D.Point(escort.Position,.02f);
            support.Rotation=new(0,-MathF.Atan2(escort.Bow.X,-escort.Bow.Y),0);
        }
        else if(support!=null) support.Visible=false;
        foreach(var departed in fleet.Keys.Where(craft=>!Course.Fleet.Contains(craft)).ToArray())
        {
            fleet[departed].QueueFree();
            fleet.Remove(departed);
        }
        for(int i=0;i<Course.Fleet.Count;i++)
        {
            var craft=Course.Fleet[i];
            if(!fleet.TryGetValue(craft,out var lighter))
            {
                lighter=BluewaterArt.Prop(Course.Country,craft.Prize?"prize":"convoy");
                lighter.Name=$"Lighter{i+1}";
                Sea.AddChild(lighter);fleet.Add(craft,lighter);
            }
            lighter.Position=NativeStage3D.Point(craft.Position,MathF.Sin(clock*2+i)*.025f);
            lighter.Rotation=new(0,-MathF.Atan2(craft.Bow.X,-craft.Bow.Y),0);
        }
        hud.QueueRedraw();
    }

    void OpenMenu()
    {
        modal=new ColorRect {Color=new Color("081c2985"),MouseFilter=Control.MouseFilterEnum.Stop};
        canvas.AddChild(modal);modal.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var center=new CenterContainer();modal.AddChild(center);center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        if(Course.Phase==ChartPhase.Passage)center.AnchorLeft=.43f;
        var panel=new PanelContainer{CustomMinimumSize=new(655,0)};panel.AddThemeStyleboxOverride("panel",HarborType.Box(new("142f3a"),new(Course.Country.Accent),24,18));center.AddChild(panel);
        var box=new VBoxContainer();box.AddThemeConstantOverride("separation",10);panel.AddChild(box);
        void Text(string line,int size,bool title=false)=>box.AddChild(HarborType.Text(line,size,title?HarborType.Cream:HarborType.Brass,title));
        void Choice(string line,Action act)
        {
            int n=options.Count+1;
            void Pick(){if(done)return;act();if(!done)Render();}
            var b=HarborType.Button($"{n}    {line}",Pick,n==1);
            box.AddChild(b);options.Add(Pick);if(n==1)b.GrabFocus();
        }
        Text($"{(string.IsNullOrEmpty(Order.Island)?Course.Region:Order.Island).ToUpperInvariant()}    /    LEG {Course.Leg} OF {Order.Legs}",15);
        if(Course.Phase is ChartPhase.Won or ChartPhase.Lost)
        {
            bool win=Course.Phase==ChartPhase.Won;
            Text(win?"A flag above the slips":"The long tow home",32,true);
            Text(win?Order.Homecoming:Course.CrewLine.Contains("convoy",StringComparison.OrdinalIgnoreCase)?Course.CrewLine:"The watch bundles the wounded into the tender and counts its purse.",19);
            Text($"{CarriedSilver+Course.Purse} silver aboard",18);
            Choice(win && LandingName!="Last Light Quay" ? "Make fast at "+LandingName : "Return to Last Light Quay",()=>Finish(win));
        }
        else if(Course.Ship.Mode==VoyageMode.Upgrade)
        {
            var ship=Course.Ship;
            Text("The gun deck",32,true);
            Text($"Level {ship.Level}    ·    Rig one fitting for this voyage.",18);
            foreach(int fit in ship.UpgradeChoices.ToArray()) Choice($"{Voyage.UpgradeNames[fit]}   ·   {ship.UpgradeBenefit(fit)}",()=>ship.Upgrade(fit));
            if(ship.UpgradeChoices.Count==0)Choice("Patch the hull",ship.TakeUpgradeHeal);
        }
        else if(Course.Phase==ChartPhase.Refit)
        {
            Text("A watch at anchor",32,true);
            Text($"Hull {Course.Ship.Health:0}/{Course.Ship.MaxHealth:0}    ·    {Course.Kits} kits    ·    {Course.Purse} silver",18);
            for(int i=0;i<3;i++){int fit=i;Choice($"{Course.RefitName(i)}   ·   {Course.RefitDetail(i)}",()=>Course.Refit(fit));}
        }
        else
        {
            Text(Order.Title,32,true);
            Text(Course.Leg==1?Order.Brief:Order.Objective,19);
            Text("Select the next passage",20,true);
            Choice("Pilot’s lee   ·   Nearby pilot mooring, lighter patrol",()=>Course.ChoosePassage(false));
            Choice("Prize water   ·   Heavier patrol, double station silver",()=>Course.ChoosePassage(true));
        }
    }

    void Finish(bool win)
    {
        if(done)return;done=true;
        if(Returned!=null)Returned(win,SilverEarned);
        else GetTree().ChangeSceneToFile("res://main.tscn");
    }
}
