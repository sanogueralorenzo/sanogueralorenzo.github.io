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
    public static Node3D Pirate(Node3D parent,Color coat,float scale=1)
    {
        var n=new Node3D{Scale=Vector3.One*scale};parent.AddChild(n);
        Source(n,"bird",Vector3.Zero,1.65f).MaterialOverride=Material(coat);
        // Original pirate accessories sit on the recovered bird silhouette.
        Box(n,new(0,1.39f,.03f),new(.86f,.12f,.59f),Ink);
        var hat=Box(n,new(0,1.58f,.03f),new(.66f,.29f,.45f),Ink);hat.RotationDegrees=new(0,0,5);
        Box(n,new(0,1.63f,.27f),new(.13f,.14f,.035f),Cream);
        Box(n,new(0,.65f,.05f),new(.55f,.16f,.4f),coat);
        var wings=Source(n,"arms",new(0,.65f,0),.9f);wings.Name="GlideWings";wings.Visible=false;
        return n;
    }
    public static Node3D Monster(Node3D parent,int kind)
    {
        var root=new Node3D();parent.AddChild(root);
        Source(root,"ghost",Vector3.Zero,kind==1?2.1f:1.6f).MaterialOverride=Material(kind==1?new("666284"):new("426f67"));
        Source(root,"skull",new(0,kind==1?1.5f:1.1f,.1f),kind==1?.72f:.58f).MaterialOverride=Material(new("d6cfaa"));
        if(kind==1){Box(root,new(0,2.22f,0),new(1,.12f,.7f),Ink);Cylinder(root,new(.9f,.85f,0),.3f,1.7f,new("9b7252"));}
        else{Box(root,new(0,1.58f,0),new(.64f,.13f,.52f),Coral);}
        return root;
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
        Cylinder(n,new(0,.17f,0),2.5f,.34f,new("798478"));
        for(int i=-1;i<=1;i+=2){Box(n,new(i*1.5f,2,0),new(.5f,4,.6f),new("765843"));Box(n,new(i*1.5f,1,.02f),new(.61f,.2f,.7f),Gold);}
        Box(n,new(0,4,0),new(3.7f,.4f,.75f),new("765843"));
        var bell=Mesh(n,new CylinderMesh{TopRadius=.28f,BottomRadius=.85f,Height=1.25f,RadialSegments=12},new(0,2.9f,0),Gold);
        Sphere(n,new(0,2.18f,0),.15f,Ink);
        var light=new OmniLight3D{Position=new(0,2.4f,0),LightColor=Gold,LightEnergy=1.5f,OmniRange=9};n.AddChild(light);
        return n;
    }
}
