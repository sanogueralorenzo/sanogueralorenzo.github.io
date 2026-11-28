using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class UnderwaysExpedition:CrewRun
{
    public CampaignOrder Order {get;set;}=FarLedger.Arcs.SelectMany(a=>a.Orders.Concat(a.Islands.SelectMany(i=>i.Outings))).First(o=>o.Underways);
    public float StartingCondition {get;set;}=1;
    public UnderwayRun Crawl {get;private set;}=null!;
    public override int SilverEarned=>Crawl?.Silver??0;
    public override bool AskShipmate(Shipmate mate)=>port?.AskShipmate(mate)??Crawl.Call(mate);
    internal KilnExpedition? Port=>port;
    public override CrewRun? ActiveWatch=>port;
    KilnExpedition? port;
    internal NativeStage3D Stage=null!;internal UnderHud Hud=null!;internal int Selected,NotePage;internal bool NotesOpen;
    readonly Dictionary<YardBeastState,Node3D> foes=[];
    Node3D captain=null!,lio=null!,vara=null!;
    MeshInstance3D veil=null!;
    AudioStreamPlayer cue=null!;
    LandingRegion region=null!;
    UnderRoomArt? art; UnderRoom? shown;UnderMarks marks=null!;
    bool returned,dodge;float previousHook;int previousSilver,previousLife;
    static bool Down(Key key)=>Input.IsPhysicalKeyPressed(key);
    public override void _Ready()
    {
        region=LandingRegion.From(Order.Region);Crawl=new(Order,Seed,Stores,Outfit,StartingCondition);Stage=new();AddChild(Stage);Stage.PaintWater(new("355860"));
        captain=ActorArt3D.BoardingParty(0);lio=ActorArt3D.BoardingParty(1);vara=ActorArt3D.BoardingParty(2);
        Stage.AddChild(captain);Stage.AddChild(lio);Stage.AddChild(vara);veil=ActorArt3D.Veil(captain);
        marks=new();Stage.AddChild(marks);
        cue=new(){VolumeDb=-18};AddChild(cue);var layer=new CanvasLayer();AddChild(layer);Hud=new(){Trip=this};layer.AddChild(Hud);Hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        previousLife=Crawl.Vitality;Render();
    }
    public override void _PhysicsProcess(double delta)
    {
        if(returned||port!=null)return;
        if(Crawl.Surface is {} yard){OpenPort(yard);return;}
        N2 move=new((Down(Key.D)||Down(Key.Right)?1:0)-(Down(Key.A)||Down(Key.Left)?1:0),(Down(Key.S)||Down(Key.Down)?1:0)-(Down(Key.W)||Down(Key.Up)?1:0));
        Crawl.Tick((float)delta,move,Down(Key.J)||Input.IsMouseButtonPressed(MouseButton.Left),dodge);dodge=false;Render();if(Crawl.Won)Settle(true);
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(returned||port!=null||Crawl.Surface!=null||input is not InputEventKey{Pressed:true,Echo:false} key)return;
        var k=key.PhysicalKeycode==Key.None?key.Keycode:key.PhysicalKeycode;
        if(Crawl.Lost){if(k==Key.E){Settle(false);GetViewport().SetInputAsHandled();}return;}
        if(k==Key.M||k==Key.Escape&&Crawl.ChartOpen){Crawl.ChartOpen=!Crawl.ChartOpen;Selected=Crawl.Here;NotesOpen=false;NotePage=0;}
        else if(Crawl.ChartOpen)
        {
            if(k==Key.J){NotesOpen=!NotesOpen;NotePage=0;}
            else if(NotesOpen&&k is Key.Up or Key.W or Key.Left or Key.A)NotePage=Math.Min(NotePage+1,Math.Max(0,(Crawl.Journal.Count-1)/6));
            else if(NotesOpen&&k is Key.Down or Key.S or Key.Right or Key.D)NotePage=Math.Max(0,NotePage-1);
            else if(k==Key.Tab)Selected=(Selected+1)%Crawl.Floor.Rooms.Length;
            else if(k is Key.Left or Key.Right or Key.Up or Key.Down or Key.A or Key.D or Key.W or Key.S)
            {
                var here=Crawl.Floor.Rooms[Selected];int x=here.X+(k is Key.D or Key.Right?1:k is Key.A or Key.Left?-1:0),y=here.Y+(k is Key.S or Key.Down?1:k is Key.W or Key.Up?-1:0);
                Selected=Crawl.Floor.Rooms.FirstOrDefault(r=>r.X==x&&r.Y==y)?.Id??Selected;
            }else return;
        }
        else if(k==Key.E)Crawl.Interact();else if(k==Key.K)Crawl.Cast();else if(k==Key.L)Crawl.Signal();else if(k==Key.Space)dodge=true;
        else if(k is Key.Key1 or Key.Key2 or Key.Key3)Crawl.Choose((int)k-(int)Key.Key1+1);
        else return;
        Hud.QueueRedraw();GetViewport().SetInputAsHandled();
    }
    void OpenPort(LandingYard yard)
    {
        Hud.Hide();RemoveChild(Stage);
        port=new KilnExpedition{Order=yard.Order,Seed=Seed,Outfit=Outfit,Stores=Stores,SuppliedYard=yard,
            CarriedSilver=CarriedSilver+Crawl.Silver-yard.Silver,Returned=ClosePort};
        AddChild(port);
    }
    void ClosePort(bool won,int outingSilver)
    {
        if(port==null)return;
        var old=port;port=null;RemoveChild(old);old.QueueFree();Crawl.ReturnBelow();
        if(!won){Settle(false);return;}
        AddChild(Stage);Stage.Lens.MakeCurrent();Hud.Show();Render();
    }
    void Settle(bool won)
    {
        if(returned)return;returned=true;
        if(Returned!=null)Returned(won,Crawl.Silver);else GetTree().ChangeSceneToFile("res://main.tscn");
    }
    public override void _ExitTree(){if(GodotObject.IsInstanceValid(Stage)&&Stage.GetParent()==null)Stage.Free();if(GodotObject.IsInstanceValid(cue)){cue.Stop();cue.Stream=null;}}
    void Play(int pitch){cue.Stream=QuayTone.Note(pitch,true);cue.Play();}
    void Render()
    {
        var y=Crawl;var room=y.Room;
        if(shown!=room)
        {
            art?.Root.QueueFree();art=new(y);Stage.AddChild(art.Root);shown=room;
            foreach(var old in foes.Values)old.QueueFree();foes.Clear();Play(62);
        }
        art!.Sync(y);Stage.Advance(y.Clock);Stage.Follow(new Vector2(y.Player.X*16, y.Player.Y*15-31),9.35f);
        Pose(captain,y.Player,y.Heading,y.Dash>0?.09f:0);Pose(lio,y.Mate,y.Hook>0?y.HookEnd-y.Mate:y.Player-y.Mate,0);Pose(vara,y.Vara,y.Flash>0?y.HookEnd-y.Vara:y.Player-y.Vara,0);
        captain.GetChild<Node3D>(0).RotationDegrees=new(0,y.Swing*142,0);captain.Visible=y.Hurt==0||(int)(y.Hurt*30)%2==0;
        veil.Visible=room.Foes.Any(f=>f.Kind==YardBeast.Guardian&&f.Position.Y>y.Player.Y&&f.Position.Y-y.Player.Y<2.0f&&Math.Abs(f.Position.X-y.Player.X)<1.20f);
        foreach(var gone in foes.Keys.Where(f=>!room.Foes.Contains(f)).ToArray()){foes[gone].QueueFree();foes.Remove(gone);}
        foreach(var f in room.Foes)
        {
            if(!foes.TryGetValue(f,out var model))
            {
                var name=f.Kind==YardBeast.Guardian?y.GuardianName:Order.Boss;var identity=Order with{Id=Order.Id+"-"+y.Depth,Boss=name,Island=Order.Island.Length>0?Order.Island:Order.Region};
                model=YardBeasts.Make(region,f.Kind,identity);Stage.AddChild(model);foes.Add(f,model);
            }
            Pose(model,f.Position,f.Heading,0);model.Rotation+=new Vector3(f.Stagger*.09f,0,f.Hit*.48f);
        }
        if(previousLife>y.Vitality)Play(41);else if(previousHook<y.Hook)Play(78);else if(previousSilver<y.Silver)Play(73);
        previousLife=y.Vitality;previousHook=y.Hook;previousSilver=y.Silver;
        marks.Redraw(y);Hud.QueueRedraw();
    }
    static void Pose(Node3D model,N2 p,N2 heading,float lift){model.Position=UnderRoomArt.Place(p,lift);if(heading.LengthSquared()>.0001f)model.Rotation=new(0,MathF.Atan2(-heading.X,-heading.Y),0);}
}
