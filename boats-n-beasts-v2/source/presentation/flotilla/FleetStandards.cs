using BoatsNBeasts.Core;
using Godot;
using static BoatsNBeasts.HarborType;

namespace BoatsNBeasts;

internal partial class FleetStandards:VBoxContainer
{
    public FlotillaPassage Passage=null!;
    NativeStage3D sea=null!;
    readonly Node3D[] boats=new Node3D[3];
    static readonly Vector3[] anchors=[new(-.89f,0,.89f),new(1.13f,0,.12f),new(-.57f,0,-1.28f)];
    float time;
    public override void _Ready()
    {
        AddThemeConstantOverride("separation",8);
        var p=Passage.Papers;
        AddChild(Text(p.Home.ToUpperInvariant()+"    /    "+p.ConsortHome.ToUpperInvariant(),16,Teal));
        var pane=new SubViewportContainer{Stretch=true,MouseFilter=Control.MouseFilterEnum.Ignore,SizeFlagsVertical=SizeFlags.ExpandFill,CustomMinimumSize=new(0,175)};AddChild(pane);
        var view=new SubViewport{Size=new(520,320),World3D=new(),HandleInputLocally=false};pane.AddChild(view);
        sea=new();view.AddChild(sea);sea.PaintWater(new("187b84"));
        int i=p.Slot;
        for(int k=0;k<boats.Length;k++)
        {
            var kind=(BoatKind)((k+i)%3);boats[k]=ActorArt3D.Boat(kind,[1,0,0,0,kind==BoatKind.Trawler?1:0,kind==BoatKind.Mage?1:0]);
            boats[k].Scale=Vector3.One*(k==1?.76f:.92f);boats[k].Position=anchors[k];sea.AddChild(boats[k]);ActorArt3D.MountCarving(boats[k],(Passage.Order.Tier+k-1)%16);
        }
        AddChild(Text(p.Vessel+"   /   "+p.ConsortVessel,24,Brass,true));
        AddChild(Text(p.Signal,18,Cream));
        var tally=new HBoxContainer();tally.AddThemeConstantOverride("separation",5);AddChild(tally);
        for(int k=0;k<6;k++)
        {
            var tick=new ColorRect{Color=k<Passage.Stage?Teal:k==Passage.Stage?Brass:new Color("365764"),CustomMinimumSize=new(14,6),SizeFlagsHorizontal=SizeFlags.ExpandFill};
            tally.AddChild(tick);
        }
    }
    public override void _Process(double delta)
    {
        time+=(float)delta;sea.Advance(time);sea.Follow(Vector2.Zero,5.25f,-.35f,.71f);
        for(int k=0;k<boats.Length;k++)
        {
            var ship=boats[k];ship.Position=anchors[k]+new Vector3(.034f*Mathf.Sin(time*.4f+k),0,.03f*Mathf.Cos(time*.42f+k));
            ship.Rotation=new(0,.78f+k*.37f+.025f*Mathf.Sin(time*.58f+k),0);ActorArt3D.AnimateBoat(ship,time+k,0,0);
        }
    }
}
