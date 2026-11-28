using BoatsNBeasts.Core;
using Godot;
using N2=System.Numerics.Vector2;

namespace BoatsNBeasts;

internal sealed class YardWorkProps
{
    readonly Node3D root=new();
    readonly List<Node3D> pieces=[];
    (int,YardPhase,int,int) built=(-1,(YardPhase)(-1),-1,-1);
    static readonly Dictionary<string,ArrayMesh> shapes=[];
    static readonly Color Brass=new("e9b063"),Iron=new("444553"),Wood=new("886750"),Paper=new("e0c89a");
    readonly Func<N2,float,Vector3> worldPoint;
    public YardWorkProps(Node3D parent,Func<N2,float,Vector3> worldPoint){this.worldPoint=worldPoint;parent.AddChild(root);}
    public static MeshInstance3D Item(string key)
    {
        if(!shapes.TryGetValue(key,out var mesh))
        {
            var b=new ActorGeometry();
            switch(key)
            {
                case "keys":
                    b.Ring(new(0,.22f,0),.16f,.036f,Brass);
                    for(int i=-1;i<=1;i++){var p=new Vector3(i*.094f,.17f,.096f);b.Tube([p,p+new Vector3(i*.035f,-.11f,.28f)],.028f,Brass,6);b.RoundBox(p+new Vector3(.042f+i*.035f,-.11f,.28f),new(.10f,.048f,.062f),.006f,Brass);}
                    break;
                case "ledger":
                    b.RoundBox(new(0,.08f,0),new(.49f,.16f,.39f),.030f,Wood);
                    b.RoundBox(new(0,.168f,0),new(.43f,.028f,.33f),.008f,Paper);
                    for(int i=0;i<4;i++)b.RoundBox(new(-.025f,.184f,-.10f+i*.058f),new(.235f,.006f,.015f),.001f,Iron);
                    break;
                case "sealed":
                    b.RoundBox(new(0,.16f,0),new(.54f,.31f,.44f),.036f,Wood);
                    foreach(float x in new[]{-.16f,.16f})b.RoundBox(new(x,.17f,0),new(.053f,.33f,.45f),.013f,Iron);
                    b.RoundBox(new(0,.23f,-.23f),new(.15f,.18f,.025f),.015f,Brass);break;
                case "stamp":
                    b.RoundBox(new(0,.08f,0),new(.56f,.16f,.48f),.035f,Iron);
                    b.Crystal(new(0,.27f,0),new(.15f,.21f,.15f),Brass);break;
                case "roll":
                    b.Tube([new(-.26f,.14f,0),new(.29f,.14f,0)],[.14f,.12f],Brass,9);
                    b.Tube([new(-.27f,.14f,0),new(-.20f,.14f,0)],.17f,Iron,9);break;
                case "weight":
                    b.Sphere(new(0,.18f,0),new(.28f,.22f,.25f),Iron);b.Ring(new(0,.37f,0),.107f,.026f,Brass);break;
                case "net":
                    b.Sphere(new(0,.11f,0),new(.21f,.20f,.19f),new("bf8054"));b.Ring(new(0,.15f,0),.20f,.024f,Brass);
                    b.Tube([new(0,.19f,0),new(0,.60f,0)],.021f,Wood,6);
                    b.Polygon([new(0,.61f,0),new(.30f,.51f,.05f),new(0,.40f,0)],new("dc6649"),Vector3.Back);break;
                case "valve":
                    b.RoundBox(new(0,.10f,0),new(.53f,.18f,.50f),.035f,Iron);
                    b.Tube([new(0,.10f,0),new(0,.43f,0)],.066f,Wood,6);
                    b.Ring(new(0,.46f,0),.23f,.033f,Brass);
                    for(int i=0;i<3;i++){float a=Mathf.Tau*i/3;b.Tube([new(0,.46f,0),new(.22f*MathF.Cos(a),.46f,.22f*MathF.Sin(a))],.017f,Brass,5);}break;
                case "mould":
                    b.RoundBox(new(0,.055f,0),new(.84f,.10f,.56f),.037f,Iron);
                    b.RoundBox(new(0,.111f,0),new(.48f,.025f,.19f),.012f,Wood);
                    foreach(float x in new[]{-.31f,.31f})b.RoundBox(new(x,.11f,0),new(.07f,.025f,.47f),.01f,Brass);
                    break;
                default:
                    b.Tube([new(0,0,0),new(0,.83f,0)],[.087f,.058f],Wood,7);
                    b.Polygon([new(0,.80f,0),new(.42f,.69f,.09f),new(.05f,.56f,0)],Brass,Vector3.Back);
                    break;
            }
            mesh=b.Mesh(DioramaSurface.Material);shapes.Add(key,mesh);
        }
        return new(){Mesh=mesh};
    }
    public void Sync(LandingYard y)
    {
        var stamp=(y.District,y.Phase,y.Branch,y.FinalIndex);
        if(built!=stamp)
        {
            built=stamp;foreach(var part in pieces)part.QueueFree();pieces.Clear();
            if(y.Phase==YardPhase.Work)
            {
                if(y.Job==LandingJob.Mould){Add("roll");Add("mould");}
                else if(y.Job==LandingJob.Escort)Add("flag");
                else
                {
                    string item=y.Job switch {LandingJob.Nets=>"net",LandingJob.Capstans=>"valve",LandingJob.Weights=>"ledger",_=>"sealed"};
                    for(int i=0;i<3;i++)Add(item);
                    if(y.Job==LandingJob.Capstans){Add("weight");Add("weight");}
                }
            }
            if(y.Phase==YardPhase.Guardian){Add("valve");Add("valve");}
            if(y.Finishing)
            {
                string item=y.FinalStep.Action switch
                {
                    LandingAction.Turn when y.FinalStep.Site==YardSite.Fallen=>"keys",
                    LandingAction.Turn when y.FinalStep.Site==YardSite.Crane=>"ledger",
                    LandingAction.Cut=>"sealed",LandingAction.Haul=>"sealed",LandingAction.Seat=>"mould",LandingAction.Guide=>"flag",_=>"valve"
                };
                Add(item);if(y.FinalStep.Action==LandingAction.Seat)Add("roll");
                if(y.FinalStep.Action==LandingAction.Brace)Add("valve");
            }
        }
        if(y.Phase==YardPhase.Work)
        {
            if(y.Job==LandingJob.Mould){Place(0,y.Billet);Place(1,y.Mould);}
            else if(y.Job==LandingJob.Escort)Place(0,y.PassengerDock);
            else
            {
                for(int i=0;i<3;i++){pieces[i].Visible=!y.Secured[i];Place(i,y.Job==LandingJob.Nets?y.Float(i):y.Mark(i),y.Job==LandingJob.Nets?-.43f+.038f*MathF.Sin(y.Clock*3+i):0);}
                if(y.Job==LandingJob.Capstans){Place(3,y.WeightAt(0));Place(4,y.WeightAt(1));}
            }
        }
        if(y.Phase==YardPhase.Guardian)for(int i=0;i<2;i++){pieces[i].Visible=y.GuardPins[i];Place(i,LandingYard.Locks[i]);}
        if(y.Finishing)
        {
            Place(0,y.FinalStep.Action==LandingAction.Guide?y.DeliverTo:y.FinalSite);
            if(y.FinalStep.Action==LandingAction.Seat)Place(1,y.Billet);
            if(y.FinalStep.Action==LandingAction.Brace)Place(1,y.ReleaseLever);
        }
    }
    void Add(string kind){var p=Item(kind);root.AddChild(p);pieces.Add(p);}
    void Place(int i,N2 pos,float lift=0)=>pieces[i].Position=worldPoint(pos,lift);
}
