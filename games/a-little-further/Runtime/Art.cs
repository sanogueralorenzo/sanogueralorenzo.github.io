using Godot;
using System.Text.Json;
using Further.Core;
using V2=System.Numerics.Vector2;
namespace Further;
public static class Art
{
    public static readonly Color Ink=new("173e49"),Gold=new("edbe67"),Cream=new("fff0d0"),Coral=new("d96954");
    static readonly Dictionary<string,ArrayMesh> cache=[];
    public static string Local(string name)=>ProjectSettings.GlobalizePath("res://Local/"+name);
    public static StandardMaterial3D Material(Color c,bool glow=false)=>new(){AlbedoColor=c,Roughness=.86f,Metallic=0,EmissionEnabled=glow,Emission=c,EmissionEnergyMultiplier=glow?.8f:0,CullMode=BaseMaterial3D.CullModeEnum.Disabled};
    public static MeshInstance3D Mesh(Node3D parent,Godot.Mesh mesh,Vector3 p,Color color)
    {
        var n=new MeshInstance3D{Mesh=mesh,Position=p,MaterialOverride=Material(color)};parent.AddChild(n);return n;
    }
    public static MeshInstance3D Box(Node3D parent,Vector3 p,Vector3 size,Color color)=>Mesh(parent,new BoxMesh{Size=size},p,color);
    public static MeshInstance3D Sphere(Node3D parent,Vector3 p,float radius,Color color)=>Mesh(parent,new SphereMesh{Radius=radius,Height=radius*2,RadialSegments=12,Rings=6},p,color);
    public static MeshInstance3D Cylinder(Node3D parent,Vector3 p,float r,float h,Color color)=>Mesh(parent,new CylinderMesh{TopRadius=r,BottomRadius=r,Height=h,RadialSegments=12},p,color);
    public static MeshInstance3D Source(Node3D parent,string key,Vector3 p,float height,float yaw=0)
    {
        if(!cache.TryGetValue(key,out var mesh))
        {
            using var doc=JsonDocument.Parse(File.ReadAllText(Local(key+".json")));var surfaces=doc.RootElement.GetProperty("surfaces");
            var points=surfaces.EnumerateArray().SelectMany(s=>s.EnumerateArray()).Select(v=>new Vector3(v[0].GetSingle(),v[1].GetSingle(),v[2].GetSingle())).ToArray();
            Basis rotation=key is "palm" or "ghost" or "skull"?new Basis(Vector3.Right,-Mathf.Pi/2):Basis.Identity;
            points=points.Select(v=>rotation*v).ToArray();float low=points.Min(v=>v.Y),high=points.Max(v=>v.Y);float scale=1/MathF.Max(.000001f,high-low);
            Vector3 center=new((points.Min(v=>v.X)+points.Max(v=>v.X))*.5f,low,(points.Min(v=>v.Z)+points.Max(v=>v.Z))*.5f);
            mesh=new();int index=0;
            foreach(var s in surfaces.EnumerateArray())
            {
                var vertices=s.EnumerateArray().Select(v=>(rotation*new Vector3(v[0].GetSingle(),v[1].GetSingle(),v[2].GetSingle())-center)*scale).ToArray();
                var st=new SurfaceTool();st.Begin(Godot.Mesh.PrimitiveType.Triangles);
                foreach(var v in vertices)st.AddVertex(v);st.GenerateNormals();st.Commit(mesh);
                Color c=key switch{ "palm"=>index==0?new("937049"):new("568b59"),"pine"=>index==0?new("755846"):new("427266"),"birch"=>index==0?new("b5a17a"):new("dba459"),"bush"=>new("71854c"),"bird"=>new("47798a"),"head" or "legs" or "arms"=>new("46586f"),"body"=>Coral,_=>new("a6a993")};
                mesh.SurfaceSetMaterial(index++,Material(c));
            }
            cache[key]=mesh;
        }
        var n=new MeshInstance3D{Mesh=mesh,Position=p,Scale=Vector3.One*height,Rotation=new(0,yaw,0)};parent.AddChild(n);return n;
    }
    public static Node3D Pirate(Node3D parent,Color coat,float scale=1,Role? role=null)
    {
        var n=new CharacterRig{Scale=Vector3.One*scale};parent.AddChild(n);n.Build(coat,(int)(coat.R*11),role);return n;
    }
    public static Node3D Monster(Node3D parent,int kind)
    {
        var root=new EnemyRig();parent.AddChild(root);root.Build(kind);return root;
    }
    public static Vector3 At(V2 p,float y)=>new(p.X,y,p.Y);
    public static void SailingRig(Node3D boat)
    {
        Cylinder(boat,new(0,2.85f,.15f),.09f,5.6f,new("644b37"));
        var st=new SurfaceTool();st.Begin(Godot.Mesh.PrimitiveType.Triangles);
        Vector3[] v=[new(.13f,5.5f,.15f),new(.13f,1.9f,.15f),new(2.6f,2.2f,.38f),new(-.13f,5.3f,.15f),new(-2.2f,2.15f,.25f),new(-.13f,2.0f,.15f)];
        foreach(var p in v)st.AddVertex(p);st.GenerateNormals();var sail=new MeshInstance3D{Mesh=st.Commit(),MaterialOverride=new ShaderMaterial{Shader=GD.Load<Shader>("res://Shaders/sail.gdshader")}};boat.AddChild(sail);
        Box(boat,new(.52f,5.5f,.16f),new(1.0f,.55f,.035f),Ink);
        Box(boat,new(.52f,5.5f,.19f),new(.21f,.23f,.03f),Cream);
        Box(boat,new(.52f,5.35f,.19f),new(.48f,.045f,.03f),Cream).RotationDegrees=new(0,0,18);
    }
    public static Node3D Shrine(Node3D parent,Vector3 p)
    {
        var n=new Node3D{Position=p};parent.AddChild(n);
        Color wood=new("685345"),bronze=new("ad8b50"),iron=new("41494a");
        for(int i=0;i<10;i++){float angle=i*Mathf.Tau/10;Source(n,"roundrock",new(MathF.Sin(angle)*2.3f,-.22f,MathF.Cos(angle)*2.1f),.65f,i);}
        for(int side=-1;side<=1;side+=2)
        {
            Box(n,new(side*1.5f,1.9f,0),new(.35f,3.8f,.42f),wood).Rotation=new(0,0,side*.035f);
            foreach(float h in new[]{.6f,2.9f})Box(n,new(side*1.5f,h,0),new(.39f,.12f,.46f),iron);
            var brace=Box(n,new(side*1.05f,3.25f,0),new(.2f,1.15f,.24f),wood);brace.Rotation=new(0,0,side*-.7f);
        }
        Box(n,new(0,3.85f,0),new(3.9f,.34f,.5f),wood);
        var hanging=new Node3D{Name="Bell",Position=new(0,3.61f,0)};n.AddChild(hanging);
        var ring=Mesh(hanging,new TorusMesh{InnerRadius=.12f,OuterRadius=.18f,Rings=12,RingSegments=6},new(0,-.1f,0),bronze);ring.Rotation=new(Mathf.Pi/2,0,0);
        // Turned outer wall and inner lip, left open around a suspended clapper.
        Vector2[] profile=[new(.16f,-.21f),new(.35f,-.29f),new(.46f,-.46f),new(.51f,-.80f),new(.65f,-1.04f),new(.85f,-1.17f),new(.86f,-1.26f),new(.76f,-1.28f),new(.59f,-1.10f),new(.43f,-.78f),new(.38f,-.45f),new(.14f,-.30f)];
        using var st=new SurfaceTool();st.Begin(Godot.Mesh.PrimitiveType.Triangles);
        for(int j=1;j<profile.Length;j++)for(int i=0;i<32;i++)
        {
            Vector3 Point(int k,int segment){var q=profile[k];float angle=segment*Mathf.Tau/32;return new(MathF.Cos(angle)*q.X,q.Y,MathF.Sin(angle)*q.X);}
            foreach(var v in new[]{Point(j-1,i),Point(j,i),Point(j,i+1),Point(j-1,i),Point(j,i+1),Point(j-1,i+1)})st.AddVertex(v);
        }
        st.GenerateNormals();hanging.AddChild(new MeshInstance3D{Mesh=st.Commit(),MaterialOverride=new StandardMaterial3D{AlbedoColor=bronze,Metallic=.6f,Roughness=.38f,CullMode=BaseMaterial3D.CullModeEnum.Disabled}});
        Cylinder(hanging,new(0,-.86f,0),.065f,.9f,iron);Sphere(hanging,new(0,-1.29f,0),.15f,bronze);
        Cylinder(n,new(.7f,1.65f,.3f),.024f,2.45f,new("b8a17a"));
        var light=new OmniLight3D{Name="Lantern",Position=new(0,2.4f,0),LightColor=Gold,LightEnergy=.65f,OmniRange=7};n.AddChild(light);
        return n;
    }
}
