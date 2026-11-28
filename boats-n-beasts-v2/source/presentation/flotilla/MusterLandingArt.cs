using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

internal static class MusterLandingArt
{
    public static readonly Color[] Flags=[new("89ded7"),new("ecad5e"),new("bda0eb")];
    public const float Floor=ShoreSculpture.Floor+.025f;
    public static Vector3 At(N2 p,float rise=0)=>new(p.X,Floor+rise,p.Y);
    static readonly Color Oak=new("755640"),Rope=new("b89a65"),Linen=new("f5dfa7");
    public static Node3D District(ConvoyLanding y)
    {
        var root=new Node3D();var rng=new Random(y.Plan.Seed);var g=new ActorGeometry();
        Color ground=new(y.Region.Ground),rock=new(y.Region.Rock),trim=new(y.Region.Trim);
        foreach(var p in y.Plan.Patches)
        {
            var rim=p.Rim.Select(q=>At(q,-.026f)).ToArray();g.Polygon(rim,ground,Vector3.Up);
            var local=rim.Select(v=>v-new Vector3(p.Center.X,.0f,p.Center.Y)).ToArray();
            var beach=new ActorGeometry();ShoreBeach.Paint(beach,local,rock,ground,y.Seed+(int)(p.Center.X*13));var sand=ShoreSculpture.Bake(beach);sand.Position=new(p.Center.X,0,p.Center.Y);root.AddChild(sand);
            for(int k=0;k<rim.Length;k++)
            {
                int j=(k+1)%rim.Length;var a=rim[k];var b=rim[j];var lo=new Vector3(a.X,-.12f,a.Z);var ll=new Vector3(b.X,-.12f,b.Z);var edge=(a-At(p.Center)).Normalized();
                g.Polygon([a,b,ll,lo],rock.Lightened(.08f*(k%3)),edge);var inside=a.Lerp(At(p.Center),.055f);var next=b.Lerp(At(p.Center),.055f);
                if(k%3!=1)g.Polygon([a+Vector3.Up*.004f,b+Vector3.Up*.004f,next,inside],ground.Lerp(trim,.38f),Vector3.Up);
            }
            for(int k=0;k<45;k++)
            {
                float a=rng.NextSingle()*Mathf.Tau,s=MathF.Sqrt(rng.NextSingle())*.87f;var at=p.Center+new N2(MathF.Cos(a)*s*p.Radius.X,MathF.Sin(a)*s*p.Radius.Y);
                var q=At(at,-.017f);g.Polygon([q,q+new Vector3(.18f+k%3*.07f,0,-.10f),q+new Vector3(.042f,0,.015f)],ground.Lerp(rock,.18f+rng.NextSingle()*.22f),Vector3.Up);
            }
        }
        foreach(var span in y.Plan.Passages)
        {
            var axis=N2.Normalize(span.To-span.From);var side=new N2(-axis.Y,axis.X);
            int boards=Math.Max(2,(int)(N2.Distance(span.From,span.To)/.32f)+1);
            for(int k=0;k<boards;k++)
            {
                float t=(float)k/boards,next=(k+.95f)/boards;var a=N2.Lerp(span.From,span.To,t);var b=N2.Lerp(span.From,span.To,next);var d=side*span.Width;
                g.Polygon([At(a-d,-.007f),At(a+d,-.007f),At(b+d,-.007f),At(b-d,-.007f)],(span.Road==YardRoad.Stone?rock:Oak).Lightened(.025f*(k%4)),Vector3.Up);
                if(k%5!=0)continue;for(int s=-1;s<=1;s+=2){var q=At(a+d*s);g.Tube([q-Vector3.Up*.36f,q+Vector3.Up*.28f],.047f,Oak,6);}
            }
        }
        foreach(var b in y.Boats)
        {
            int i=b.Index;
            Add(root,Standard(Flags[i]),y.Station(i));
            for(int j=0;j<3;j++)Add(root,YardWorkProps.Item(j==0?"valve":j==1?"flag":"mould"),y.Mark(i,j));
            Add(root,YardWorkProps.Item("mould"),y.BraceSeat(b));
            foreach(bool gate in new[]{false,true})
            {
                var axis=y.Channel(i,gate);var side=new N2(-axis.Y,axis.X);var bank=y.Bank(i,gate);
                for(int j=0;j<5;j++){var a=bank+axis*(j*.21f-.27f);var end=a+axis*.195f;
                    g.Polygon([At(a-side*.28f,-.055f),At(a+side*.28f,-.055f),At(end+side*.28f,-.055f),At(end-side*.28f,-.055f)],Oak.Lightened(.06f*(j%3)),Vector3.Up);}
            }
            Add(root,YardWorkProps.Item("valve"),y.GatePost(i));
        }
        Add(root,YardWorkProps.Item("ledger"),y.Plan.Wayhouse);Add(root,YardWorkProps.Item("net"),y.Plan.Pocket);
        for(int mark=0;mark<3;mark++)Add(root,YardWorkProps.Item("sealed"),y.SealSite(mark));
        Add(root,TideHall.Build(y.Region),y.Plan.Patches[0].Closest(y.Plan.Patches[0].Center+new N2(2.6f,-2.8f))).Scale=Vector3.One*.65f;
        root.AddChild(ShoreSculpture.Bake(g));return root;
    }
    public static Node3D Add(Node3D host,Node3D part,N2 at,float rise=0){part.Position=At(at,rise);host.AddChild(part);return part;}
    public static Node3D Standard(Color dye)
    {
        var g=new ActorGeometry();g.Tube([new(0,0,0),new(0,1.46f,0)],.041f,Oak,8);
        g.Polygon([new(0,1.38f,0),new(.57f,1.31f,.04f),new(.33f,1.14f,.02f),new(.53f,1.02f,.04f),new(0,1.07f,0)],dye,Vector3.Back);
        g.Polygon([new(.07f,1.33f,.008f),new(.21f,1.24f,.014f),new(.08f,1.14f,.008f)],Linen,Vector3.Back);return ShoreSculpture.Bake(g);
    }
    public static Node3D Breastwork(Color dye)
    {
        var g=new ActorGeometry();
        for(int k=0;k<5;k++)
        {
            float x=-.48f+.24f*k,height=.45f+.06f*(k%2);
            g.RoundBox(new(x,height*.5f,0),new(.20f,height,.15f),.025f,Oak.Lightened(k*.026f));
            g.Polygon([new(x-.10f,height-.14f,-.081f),new(x+.10f,height-.14f,-.081f),new(x+.10f,height-.073f,-.081f),new(x-.10f,height-.073f,-.081f)],dye,Vector3.Forward);
        }
        g.Tube([new(-.50f,.09f,-.089f),new(.46f,.35f,-.089f)],.031f,Linen,6);return ShoreSculpture.Bake(g);
    }
    public static Node3D Vessel(int i)
    {
        var hull=ActorArt3D.ShoreSkiff();var flag=Standard(Flags[i]);flag.Position=new(0,.22f,.08f);hull.AddChild(flag);
        var g=new ActorGeometry();var dye=Flags[i];
        g.Tube([new(-.34f,.87f,0),new(.38f,.87f,0)],.025f,Rope,6);
        g.Polygon([new(-.28f,.85f,0),new(.33f,.86f,0),new(.27f,.47f,.10f),new(-.24f,.47f,.10f)],dye,Vector3.Back);
        if(i==0)
        {
            g.RoundBox(new(0,.32f,-.27f),new(.69f,.23f,.56f),.075f,dye.Darkened(.32f));
            g.Polygon([new(-.41f,.44f,-.58f),new(0,.65f,-.58f),new(0,.65f,.04f),new(-.41f,.44f,.04f)],dye,Vector3.Up);
            g.Polygon([new(0,.65f,-.58f),new(.41f,.44f,-.58f),new(.41f,.44f,.04f),new(0,.65f,.04f)],dye.Lightened(.12f),Vector3.Up);
        }
        else if(i==1)
        {
            for(int k=-1;k<=1;k+=2){g.Tube([new(k*.30f,.22f,-.32f),new(k*.71f,.16f,-.32f)],.034f,Rope);g.Tube([new(k*.30f,.22f,.34f),new(k*.71f,.16f,.34f)],.034f,Rope);g.Sphere(new(k*.72f,.12f,.03f),new(.11f,.095f,.61f),dye,9,5);}
        }
        else
        {
            for(int k=-1;k<=1;k+=2){g.Tube([new(k*.23f,.20f,.47f),new(k*.37f,.83f,.63f)],.036f,Oak);g.Tube([new(k*.37f,.83f,.63f),new(0,.95f,.63f)],.024f,Rope);}
            g.Polygon([new(-.35f,.79f,.63f),new(.35f,.79f,.63f),new(.19f,.46f,.45f),new(-.16f,.46f,.45f)],dye,Vector3.Back);
        }
        hull.AddChild(ShoreSculpture.Bake(g));return hull;
    }
}
