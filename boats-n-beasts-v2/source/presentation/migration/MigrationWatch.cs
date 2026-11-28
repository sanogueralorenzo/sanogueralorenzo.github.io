using Godot;
using BoatsNBeasts.Core;
using V2=System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class MigrationWatch : CrewRun
{
    public CampaignOrder Order {get;set;}=FarLedger.Arcs[8].Islands[0].Outings[0];
    public override bool AskShipmate(Shipmate mate) => !Chart && !Drive.Won && !Drive.Lost && Drive.Ship.CallShipmate(mate);
    public override int SilverEarned=>Drive?.Purse??0;
    internal ReefDrive Drive {get;private set;}=null!;
    internal OceanView3D Ocean {get;private set;}=null!;
    internal bool Chart {get;private set;}=true;
    internal int Target {get;private set;}
    internal int Total => Drive.Herd.Length+1+Drive.Grass.Length;
    internal (V2 Position,string Name) Mark(int i)=>i<Drive.Herd.Length?(Drive.Herd[i].Position,Drive.Herd[i].Name)
        :i==Drive.Herd.Length?(Drive.Nursery,"Nursery mother"):(Drive.Grass[i-Drive.Herd.Length-1],"Kelp bed");
    Node3D[] calves=[],beds=[];
    AudioStreamPlayer horn=null!,echo=null!;
    TidePilot book=null!;
    bool done;
    int echoIndex;
    float nextEcho;
    ReefCalf? listening;
    public override void _Ready()
    {
        Drive=new(Order,Seed,Stores,Outfit,Vessel);
        var water=SeaCountry.At(Order.Region,Order.Island);
        Ocean=new(){Figurehead=Figurehead,Voyage=Drive.Ship,CustomPlace=p=>BluewaterCoast.Build(p,water,false)};AddChild(Ocean);Ocean.OpenChart();
        Ocean.PaintWater(BluewaterCoast.Water(water.Climate));
        calves=Drive.Herd.Select(c=>ReefHerdArt.Calf(c.Dye)).ToArray();
        beds=Drive.Grass.Select(p=>ReefHerdArt.Kelp()).ToArray();
        foreach(var c in calves)Ocean.AddChild(c);
        for(int i=0;i<beds.Length;i++){Ocean.AddChild(beds[i]);beds[i].Position=NativeStage3D.Point(Drive.Grass[i]);}
        var mother=ReefHerdArt.Calf(Order.Tier,true);Ocean.AddChild(mother);
        mother.Position=NativeStage3D.Point(Drive.Nursery);mother.RotationDegrees=new(0,-32,0);
        horn=new(){VolumeDb=-16};echo=new(){VolumeDb=-24};AddChild(horn);AddChild(echo);
        var layer=new CanvasLayer();AddChild(layer);
        book=new(){Trip=this};layer.AddChild(book);book.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        Ocean.Advance(.016f);Paint();
    }
    internal void Choose(int i){Target=Math.Clamp(i,0,Total-1);book.QueueRedraw();}
    internal void Fold(){if(!Drive.Won && !Drive.Lost && Drive.Ship.Mode!=VoyageMode.Upgrade){Chart=!Chart;book.QueueRedraw();}}
    static bool Held(Key a,Key b)=>Input.IsPhysicalKeyPressed(a)||Input.IsPhysicalKeyPressed(b);
    public override void _PhysicsProcess(double delta)
    {
        if(done || Chart || Drive.Won || Drive.Lost || Drive.Ship.Mode!=VoyageMode.Sailing)return;
        var ship=Drive.Ship;var h=Drive.Home;
        V2 move=new((Held(Key.D,Key.Right)?1:0)-(Held(Key.A,Key.Left)?1:0),(Held(Key.S,Key.Down)?1:0)-(Held(Key.W,Key.Up)?1:0));
        bool click=Input.IsMouseButtonPressed(MouseButton.Left);
        var enemy=ship.Enemies.Where(e=>e.Health>0).MinBy(e=>V2.DistanceSquared(ship.Position,e.Position));
        V2? aim=click?Ocean.WorldPoint(GetViewport().GetMousePosition()):enemy?.Position;
        Drive.Tick((float)delta,new(move,Input.IsPhysicalKeyPressed(Key.Shift),click||Input.IsPhysicalKeyPressed(Key.Space),aim));
        foreach(var ev in ship.Events)Ocean.Effect(ev);ship.Events.Clear();
        if(Drive.Home>h)Target=Drive.Home==Drive.Herd.Length?Drive.Herd.Length:Array.FindIndex(Drive.Herd,c=>c.Mood!=CalfMood.Home);
        var singer=Drive.Singer;
        if(singer!=listening){listening=singer;echoIndex=0;nextEcho=.4f;}
        if(singer!=null)
        {
            nextEcho-=(float)delta;
            if(nextEcho<=0)
            {
                Play(echo,singer.Song[echoIndex]);echoIndex=(echoIndex+1)%singer.Song.Length;nextEcho=echoIndex==0?3.5f:.48f;
            }
        }
        Ocean.Advance((float)delta);Paint();
    }
    void Paint()
    {
        for(int i=0;i<calves.Length;i++)
        {
            var c=Drive.Herd[i];var at=c.Position;
            if(c.Mood==CalfMood.Home)at=Drive.Nursery+new V2(-156+i*103,140);
            calves[i].Position=NativeStage3D.Point(at,.037f*MathF.Sin(Drive.Time*2+i));
            calves[i].Rotation=new(.025f*MathF.Sin(Drive.Time+i),MathF.Atan2(-c.Bow.X,-c.Bow.Y),.025f*MathF.Cos(Drive.Time+i));
        }
        for(int i=0;i<beds.Length;i++)beds[i].Visible=!Drive.Cut(i);
        book.QueueRedraw();
    }
    static void Play(AudioStreamPlayer player,int note)
    {player.Stream=QuayTone.Note(note switch {1=>55,2=>62,_=>69},true);player.Play();}
    internal void Settle()
    {
        if(done || !(Drive.Won||Drive.Lost))return;done=true;
        if(Returned!=null)Returned(Drive.Won,Drive.Purse);else GetTree().ChangeSceneToFile("res://main.tscn");
    }
    internal void Refit(int index)
    {
        var ship=Drive.Ship;
        if(ship.UpgradeChoices.Count==0)ship.TakeUpgradeHeal();
        else if(index>=0 && index<ship.UpgradeChoices.Count)ship.Upgrade(ship.UpgradeChoices[index]);book.QueueRedraw();
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(done||input is not InputEventKey{Pressed:true,Echo:false} e)return;
        var key=e.PhysicalKeycode==Key.None?e.Keycode:e.PhysicalKeycode;
        int n=(int)key-(int)Key.Key1;
        if(Drive.Won||Drive.Lost){if(key!=Key.Enter)return;Settle();}
        else if(Drive.Ship.Mode==VoyageMode.Upgrade){if(n<0 && key!=Key.Enter)return;Refit(n);}
        else if(key==Key.M || Chart && key==Key.Enter)Fold();
        else if(key==Key.Tab || Chart && key==Key.Right)Choose((Target+1)%Total);
        else if(Chart && key==Key.Left)Choose((Target+Total-1)%Total);
        else if(Chart)return;
        else if(n is >=0 and <3)
        {
            var c=Drive.Singer;Drive.Note(n+1);Play(horn,n+1);
            if(c?.Mood==CalfMood.Following){Target=Drive.Herd.Length;nextEcho=3;}
        }
        else if(key==Key.Q){Drive.Call();Play(horn,1);}
        else if(key==Key.E)Drive.Tend();
        else if(key==Key.R)Drive.Patch();
        else return;
        book.QueueRedraw();GetViewport().SetInputAsHandled();
    }
}
