using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

internal partial class UnderMarks:MeshInstance3D
{
    readonly ImmediateMesh brush=new();
    readonly StandardMaterial3D ink=new(){ShadingMode=BaseMaterial3D.ShadingModeEnum.Unshaded,VertexColorUseAsAlbedo=true,Transparency=BaseMaterial3D.TransparencyEnum.Alpha,CullMode=BaseMaterial3D.CullModeEnum.Disabled};
    static readonly Color Gold=new("f1c27c"),Mint=new("a2ead1"),Ivory=new("ffebba"),Rose=new("df635b91");
    public override void _Ready(){Mesh=brush;CastShadow=ShadowCastingSetting.Off;ExtraCullMargin=15;}
    void Quad(N2 a,N2 b,N2 c,N2 d,Color color,float lift)
    {
        brush.SurfaceSetColor(color);foreach(var p in new[]{a,b,c,a,c,d})brush.SurfaceAddVertex(UnderRoomArt.Place(p,lift));
    }
    void Arc(N2 p,float inner,float outer,float start,float span,Color color,float up=.042f)
    {
        if(outer<=inner)return;int count=Math.Max(5,(int)MathF.Ceiling(span*7));for(int i=0;i<count;i++)
        {float a=start+span*i/count,b=start+span*(i+1)/count;N2 s=new(MathF.Cos(a),MathF.Sin(a)),e=new(MathF.Cos(b),MathF.Sin(b));Quad(p+s*inner,p+s*outer,p+e*outer,p+e*inner,color,up);}
    }
    void Line(N2 a,N2 b,float width,Color color,float up=.045f)
    {var axis=b-a;if(axis.LengthSquared()<.001f)return;var side=N2.Normalize(new(-axis.Y,axis.X))*width;Quad(a-side,b-side,b+side,a+side,color,up);}
    public void Redraw(UnderwayRun run)
    {
        brush.ClearSurfaces();brush.SurfaceBegin(Mesh.PrimitiveType.Triangles,ink);
        Arc(run.Player,.31f,.35f,0,Mathf.Tau,Mint);
        foreach(var d in run.Floor.Exits(run.Here))
        {
            var p=run.Floor.Threshold(run.Here,d);var u=N2.Normalize(p);var side=new N2(-u.Y,u.X);
            var c=run.CanOpen(d)?Mint:Gold;Line(p-u*.33f-side*.21f,p-u*.12f,.030f,c);Line(p-u*.12f,p-u*.33f+side*.21f,.030f,c);
        }
        foreach(var (p,_) in run.WorkMarks())Arc(p,.34f,.38f,0,Mathf.Tau,Gold);
        if(run.Room.Pipes is {} pipes)
            for(int i=0;i<16;i++)
            {
                var p=DrainageBoard.At(i);
                if(pipes.Outlets.Contains(i))Arc(p,.23f,.27f,0,Mathf.Tau,pipes.Wet[i]?Mint:Gold,.096f);
                if(!pipes.Wet[i])continue;
                for(int d=0;d<4;d++)if((pipes.Ports(i)&(1<<d))!=0)
                {
                    N2 dir=new(MathF.Sin(d*Mathf.Pi/2),-MathF.Cos(d*Mathf.Pi/2));Line(p+dir*.12f,p+dir*.45f,.035f,Mint,.245f);
                }
            }
        if(run.Room.Rail is {} rail)
        {
            for(int i=0;i<7;i++)
            {
                var p=rail.At(i);int to=i*2+(rail.Divert[i]?2:1);Line(p,N2.Lerp(p,rail.At(to),.45f),.048f,Mint,.14f);
            }
            if(!rail.Done)Arc(rail.At(7+rail.Asked),.33f,.37f,0,Mathf.Tau,Gold,.18f);
        }
        if(run.Room.Board is {Mirror:true} mirror)
        {
            for(int i=1;i<mirror.Ray.Count;i++){Line(mirror.Ray[i-1],mirror.Ray[i],.048f,new("c88a3e82"),.35f);Line(mirror.Ray[i-1],mirror.Ray[i],.017f,Ivory,.36f);}
        }
        if(run.LoadLive){for(int i=0;i<2;i++)Arc(run.LoadAt(i),.34f,.44f,0,Mathf.Tau,Rose);}
        foreach(var a in run.Attacks)
        {
            var fill=a.Fired?new Color("f79869be"):Rose;
            if(a.Shape==AttackShape.Lane)
            {
                var axis=N2.Normalize(a.Target-a.Origin);var side=new N2(-axis.Y,axis.X)*a.Radius;
                Quad(a.Origin-side,a.Target-side,a.Target+side,a.Origin+side,fill,.049f);Line(a.Origin-side,a.Target-side,.026f,Ivory);Line(a.Origin+side,a.Target+side,.026f,Ivory);
                var front=N2.Lerp(a.Origin,a.Target,a.Windup);Line(front-side,front+side,.028f,Gold);continue;
            }
            float begin=0,span=Mathf.Tau,inner=a.Shape==AttackShape.Ring?a.Inner:.006f;
            if(a.Shape==AttackShape.Fan){var d=a.Target-a.Origin;span=2*MathF.Acos(a.Inner);begin=MathF.Atan2(d.Y,d.X)-span*.5f;}
            Arc(a.Origin,inner,a.Radius,begin,span,fill,.048f);Arc(a.Origin,a.Radius-.039f,a.Radius,begin,span,Ivory,.053f);
            float radius=Mathf.Lerp(inner,a.Radius,a.Windup);Arc(a.Origin,Math.Max(inner,radius-.040f),radius,begin,span,Gold,.057f);
        }
        if(run.Swing>0)Arc(run.Player,.77f,.86f,MathF.Atan2(run.Heading.Y,run.Heading.X)-1.19f,2.38f,Ivory,.22f);
        if(run.Hook>0)Line(run.Mate,run.HookEnd,.023f,Ivory,.48f);
        if(run.Flash>.20f&&run.Room.Foes.Count>0)Line(run.Vara,run.HookEnd,.022f,Gold,.53f);
        brush.SurfaceEnd();
    }
}
