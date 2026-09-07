using Godot;
using Further.Core;
namespace Further;
public sealed class Effects(Node3D root)
{
    readonly List<(Node3D Node,Vector3 Velocity,float Life,float Max)> active=[];
    readonly Random random=new(741);
    public void Burst(Vector3 position,Color color,int count=7,float force=3)
    {
        for(int i=0;i<count;i++)
        {
            if(active.Count>=220)break;
            var n=Art.Box(root,position,Vector3.One*.13f,color);
            Vector3 v=new((float)random.NextDouble()*2-1,(float)random.NextDouble()*1.5f+.5f,(float)random.NextDouble()*2-1);
            active.Add((n,v*force,.5f,.5f));
        }
    }
    public void Shot(Hit hit,Run run)
    {
        if(active.Count>=218)return;
        Color c=hit.Kind switch{2=>new("87ded5"),3=>Art.Coral,-1=>new("de5847"),_=>Art.Gold};
        Vector3 a=Art.At(hit.From,run.World.Height(hit.From)+1.1f),b=Art.At(hit.To,run.World.Height(hit.To)+1.1f);
        var tracer=Art.Box(root,(a+b)*.5f,new(.055f,.055f,MathF.Max(.01f,a.DistanceTo(b))),c);if(a.DistanceTo(b)>.01f)tracer.LookAt(b);
        tracer.MaterialOverride=Art.Material(c,true);active.Add((tracer,Vector3.Zero,.13f,.13f));
        var label=new Label3D{Text=((int)hit.Damage).ToString(),Position=b+Vector3.Up,FontSize=42,PixelSize=.009f,Modulate=c,OutlineSize=8,Billboard=BaseMaterial3D.BillboardModeEnum.Enabled,NoDepthTest=true};root.AddChild(label);active.Add((label,Vector3.Up*1.5f,.65f,.65f));Burst(b,c,hit.Kill?12:4,hit.Kill?5:3);
    }
    public void Step(float dt)
    {
        for(int i=active.Count-1;i>=0;i--){var a=active[i];float life=a.Life-dt;if(life<=0){a.Node.QueueFree();active.RemoveAt(i);continue;}a.Node.Position+=a.Velocity*dt;if(a.Node is not Label3D)a.Node.Scale=Vector3.One*MathF.Min(1,life/a.Max*2);active[i]=(a.Node,a.Velocity,life,a.Max);}
    }
    public void Shift(System.Numerics.Vector2 shift){foreach(var a in active)a.Node.Position-=new Vector3(shift.X,0,shift.Y);}
}
