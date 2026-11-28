using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class MusterLanding:CrewRun
{
    public CampaignOrder Order {get;set;}=FreeFleet.CinderCharter();
    public float StartingCondition {get;set;}=1;
    public float Condition=>Muster?.Condition??StartingCondition;
    public ConvoyLanding Muster{get;private set;}=null!;
    public override int SilverEarned=>Muster?.Silver??0;
    public override bool AskShipmate(Shipmate mate)=>!MapOpen&&Muster.CallShipmate(mate);
    internal NativeStage3D Stage=null!;
    internal bool MapOpen;
    MusterLandingHud hud=null!;
    readonly Node3D[] ships=new Node3D[3],workers=new Node3D[3],screens=new Node3D[3],seats=new Node3D[3],freight=new Node3D[3];
    readonly Dictionary<YardBeastState,Node3D> foes=[];
    readonly List<Node3D> coins=[];
    Node3D captain=null!,mate=null!,vara=null!,family=null!,cargo=null!,district=null!;
    AudioStreamPlayer cue=null!;MeshInstance3D silhouette=null!;
    int drawn=-1,lastHealth,lastSilver;float oldHook;bool returned,dodge;
    public override void _Ready()
    {
        Muster=new(Order,Seed,Stores,Outfit,StartingCondition);Stage=new();AddChild(Stage);Stage.PaintWater(new("428f91"));lastHealth=Muster.Health;
        captain=ActorArt3D.BoardingParty(0);mate=ActorArt3D.BoardingParty(1);vara=ActorArt3D.BoardingParty(2);
        foreach(var person in new[]{captain,mate,vara})Stage.AddChild(person);
        silhouette=ActorArt3D.Veil(captain);
        for(int i=0;i<3;i++)
        {
            ships[i]=MusterLandingArt.Vessel(i);Stage.AddChild(ships[i]);
            screens[i]=MusterLandingArt.Breastwork(MusterLandingArt.Flags[i]);screens[i].Position=new(0,.18f,-.58f);ships[i].AddChild(screens[i]);
            seats[i]=ActorArt3D.LandingParty(2);seats[i].Scale=Vector3.One*.59f;seats[i].Position=new(-.16f,.19f,.28f);ships[i].AddChild(seats[i]);
            freight[i]=YardWorkProps.Item("sealed");freight[i].Scale=Vector3.One*.50f;freight[i].Position=new(.16f,.19f,-.24f);ships[i].AddChild(freight[i]);
            workers[i]=ActorArt3D.LandingParty((i+1)%3);
            var hand=MusterLandingArt.Standard(MusterLandingArt.Flags[i]);hand.Scale=Vector3.One*.66f;hand.Position=new(.31f,.01f,.13f);workers[i].AddChild(hand);Stage.AddChild(workers[i]);
        }
        family=ActorArt3D.LandingParty(2);var child=ActorArt3D.LandingParty(1);child.Scale=Vector3.One*.65f;child.Position=new(.37f,0,.16f);family.AddChild(child);Stage.AddChild(family);
        cargo=YardWorkProps.Item("sealed");Stage.AddChild(cargo);
        var canvas=new CanvasLayer();AddChild(canvas);hud=new(){Run=this};canvas.AddChild(hud);hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        cue=new(){VolumeDb=-19};AddChild(cue);Render();
    }
    public override void _PhysicsProcess(double delta)
    {
        if(returned||MapOpen)return;
        N2 move=new((Held(Key.D)||Held(Key.Right)?1:0)-(Held(Key.A)||Held(Key.Left)?1:0),(Held(Key.S)||Held(Key.Down)?1:0)-(Held(Key.W)||Held(Key.Up)?1:0));
        Muster.Tick((float)delta,move,Held(Key.J)||Input.IsMouseButtonPressed(MouseButton.Left),dodge);dodge=false;Render();
        if(Muster.Won)Settle(true);
    }
    static bool Held(Key k)=>Input.IsPhysicalKeyPressed(k);
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(returned||input is not InputEventKey{Pressed:true,Echo:false} ev)return;
        var k=ev.PhysicalKeycode==Key.None?ev.Keycode:ev.PhysicalKeycode;
        if(Muster.Lost){if(k==Key.E){Settle(false);GetViewport().SetInputAsHandled();}return;}
        if(k==Key.M||k==Key.Escape&&MapOpen)MapOpen=!MapOpen;
        else if(MapOpen)return;
        else if(k==Key.K)Muster.Hook();else if(k==Key.L)Muster.Signal();else if(k==Key.E)Muster.Interact();else if(k==Key.Space)dodge=true;
        else if(k is Key.Key1 or Key.Key2 or Key.Key3)Muster.Choose((int)k-(int)Key.Key1+1);else return;
        hud.QueueRedraw();GetViewport().SetInputAsHandled();
    }
    void Settle(bool win){if(returned)return;returned=true;if(Returned!=null)Returned(win,Muster.Silver);else GetTree().ChangeSceneToFile("res://main.tscn");}
    public override void _ExitTree(){if(GodotObject.IsInstanceValid(cue)){cue.Stop();cue.Stream=null;}}
    void Render()
    {
        var y=Muster;
        if(drawn!=y.District)
        {
            district?.QueueFree();district=MusterLandingArt.District(y);Stage.AddChild(district);drawn=y.District;
            foreach(var f in foes.Values)f.QueueFree();foes.Clear();
        }
        Stage.Advance(y.Clock);Stage.Follow(new Vector2(y.Player.X*100,y.Player.Y*100-57),9.42f);
        Pose(captain,y.Player,y.Heading,y.Dashing>0?.065f:0);Pose(mate,y.Mate,y.EventTime>0?y.LineEnd-y.Mate:y.Player-y.Mate);Pose(vara,y.Gunner,y.Flash>0?y.LineEnd-y.Gunner:y.Player-y.Gunner);
        captain.GetChild<Node3D>(0).RotationDegrees=new(0,y.Swing*149,0);captain.Visible=y.Hurt<=0||(int)(y.Hurt*29)%2==0;
        silhouette.Visible=y.Foes.Any(f=>f.Kind==YardBeast.Guardian&&f.Position.Y>=y.Player.Y&&f.Position.Y-y.Player.Y<2&&Math.Abs(f.Position.X-y.Player.X)<1.18f);
        bool gate=y.Phase>=MusterPhase.Guard;
        for(int i=0;i<3;i++)
        {
            var b=y.Boats[i];var water=y.Mooring(i,gate);var dir=y.Channel(i,gate);
            float slip=b.Through&&i!=y.Lead?Math.Min(6,(y.Clock-b.SailedAt)*1.2f):0;
            var loc=water+dir*slip;
            if(b.LeftDock>=0&&!b.Through&&y.ChannelBoard==null)
            {
                float tMoor=Math.Clamp((y.Clock-b.LeftDock)/3.0f,0,1);
                var start=y.Mooring(i,false);var end=y.Mooring(i,true);var head=N2.Lerp(start,end,tMoor);
                var side=Unit(new N2(end.Y-start.Y,start.X-end.X));loc=head+side*(MathF.Sin(tMoor*Mathf.Pi)*(5.0f+.75f*i));
            }
            screens[i].Visible=b.Timbers>0;seats[i].Visible=b.People>0;freight[i].Visible=b.Stores>0||y.Carrier==i&&!y.CargoDelivered;
            if(y.ChannelBoard is {} basin&&y.Phase==MusterPhase.Tideway)
            {
                float advance=Math.Clamp((y.Clock-basin.LastSignalAt)*2.6f,0,1);
                float lane=Mathf.Lerp(basin.PreviousLane[i],basin.Lane[i],advance);float row=Mathf.Lerp(basin.PreviousRow[i],basin.Row[i],advance);
                loc=N2.Lerp(water,y.Mooring(1,true)+new N2((lane-2)*1.10f,-row*.93f),Math.Clamp(row,0,1));
            }
            ships[i].Position=new(loc.X,.018f+.018f*MathF.Sin(y.Clock*1.5f+i),loc.Y);
            ships[i].Rotation=new(0,MathF.Atan2(-dir.X,-dir.Y),.024f*MathF.Sin(y.Clock*1.7f+i));
            ships[i].Visible=b.Hull>0;workers[i].Visible=b.Hull>0&&!b.Through;Pose(workers[i],b.Worker,y.Player-b.Worker);
        }
        family.Visible=y.Team is {Role:MusterRole.Escort};
        if(y.Team is {} t)
        {
            Pose(family,t.Passenger,y.Player-t.Passenger);cargo.Visible=t.Role is MusterRole.Fortify or MusterRole.Salvage&&t.Step>=2;
            if(cargo.Visible){Pose(cargo,t.Load,N2.UnitY,.08f);cargo.Scale=t.Role==MusterRole.Fortify?new(1.85f,.64f,.73f):Vector3.One;}
        }else if(y.Phase==MusterPhase.Consign&&y.FreightStep==2)
        {
            cargo.Visible=true;cargo.Scale=Vector3.One*.87f;Pose(cargo,y.Freight,y.Player-y.Freight,.09f);
        }else cargo.Visible=false;
        foreach(var f in foes.Keys.Where(f=>!y.Foes.Contains(f)).ToArray()){foes[f].QueueFree();foes.Remove(f);}
        foreach(var f in y.Foes){if(!foes.TryGetValue(f,out var model)){model=YardBeasts.Make(y.Region,f.Kind,Order with{Island=y.DistrictName});Stage.AddChild(model);foes.Add(f,model);}Pose(model,f.Position,f.Heading);model.Rotation+=new Vector3(f.Stagger*.035f,0,f.Hit*.52f);}
        while(coins.Count>y.Drops.Count){coins[^1].QueueFree();coins.RemoveAt(coins.Count-1);}
        while(coins.Count<y.Drops.Count){var coin=YardWorkProps.Item("weight");coin.Scale=Vector3.One*.48f;Stage.AddChild(coin);coins.Add(coin);}
        for(int i=0;i<coins.Count;i++)coins[i].Position=MusterLandingArt.At(y.Drops[i],.09f);
        int pitch=lastHealth>y.Health?42:oldHook<y.EventTime?78:lastSilver<y.Silver?73:0;if(pitch>0){cue.Stream=QuayTone.Note(pitch,true);cue.Play();}
        lastHealth=y.Health;lastSilver=y.Silver;oldHook=y.EventTime;hud.QueueRedraw();
    }
    static N2 Unit(N2 v)=>v.LengthSquared()>.001f?N2.Normalize(v):N2.UnitY;
    static void Pose(Node3D part,N2 p,N2 dir,float lift=0){part.Position=MusterLandingArt.At(p,lift);if(dir.LengthSquared()>.006f)part.Rotation=new(0,MathF.Atan2(-dir.X,-dir.Y),0);}
}
