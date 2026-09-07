using Godot;
using Further.Core;
namespace Further;
public sealed class Ocean
{
    readonly MeshInstance3D mesh;
    readonly ShaderMaterial material;
    readonly List<(Vector2 P,float Time,float Strength,Vector2 Dir)> knots=[];
    float emitTime;
    public Ocean(Node3D parent)
    {
        var shader=new Shader{Code=File.ReadAllText(Art.Local("ocean.gdshader"))};material=new(){Shader=shader};
        mesh=new(){Mesh=new PlaneMesh{Size=new(1500,1500),SubdivideWidth=300,SubdivideDepth=300},MaterialOverride=material,CastShadow=GeometryInstance3D.ShadowCastingSetting.Off,ExtraCullMargin=10};parent.AddChild(mesh);
    }
    public void Update(Run run)
    {
        mesh.Position=new(MathF.Round(run.Position.X/5)*5,0,MathF.Round(run.Position.Y/5)*5);
        material.SetShaderParameter("clock_time",(float)run.Time);
        float[] phases=PrivateSources.Waves.Select(w=>(float)((Math.Tau/w[3]*(w[0]*run.Ship.OriginX+w[1]*run.Ship.OriginZ)/Math.Sqrt(w[0]*w[0]+w[1]*w[1]))%Math.Tau)).ToArray();
        material.SetShaderParameter("origin_phases",phases);
        material.SetShaderParameter("origin_offset",new Vector2(run.World.Origin.X*World.ChunkSize,run.World.Origin.Z*World.ChunkSize));
        if(run.Time>emitTime && run.Mode==RunMode.Sailing && run.Ship.Velocity.Length()>1)
        {
            emitTime=(float)run.Time+.2f;knots.Insert(0,(new(run.Ship.Position.X,run.Ship.Position.Y),(float)run.Time,Math.Clamp(run.Ship.Velocity.Length()/16,0,1),new(MathF.Sin(run.Ship.Heading),MathF.Cos(run.Ship.Heading))));
            if(knots.Count>24)knots.RemoveAt(24);
        }
        Vector4[] wakes=new Vector4[24],dirs=new Vector4[24];for(int i=0;i<knots.Count;i++){var k=knots[i];wakes[i]=new(k.P.X,k.P.Y,k.Time,k.Strength);dirs[i]=new(k.Dir.X,k.Dir.Y,0,0);}
        material.SetShaderParameter("wake",wakes);material.SetShaderParameter("wake_direction",dirs);material.SetShaderParameter("wake_count",knots.Count);
    }
    public void Shift(System.Numerics.Vector2 shift)
    {
        for(int i=0;i<knots.Count;i++){var k=knots[i];knots[i]=(k.P-new Vector2(shift.X,shift.Y),k.Time,k.Strength,k.Dir);}
    }
}
