using Godot;
using Further.Core;
namespace Further;
public static class Discoveries
{
    static readonly Color wood=new("67503a"),canvas=new("c3b491"),iron=new("3d4b4d");
    public static List<Node3D> Build(Node3D parent,Island island)
    {
        var routes=IslandLayout.Routes(island);var lids=new List<Node3D>();
        for(int i=1;i<routes.Length;i++)
        {
            var p=routes[i][^1];var n=new Node3D{Position=Art.At(p,World.Height(island,island.Center+p)),Rotation=new(0,(island.Seed%7+i)*.5f,0)};parent.AddChild(n);
            var offset=new Vector3(-2.8f,0,-1.5f);var rotated=n.Basis*offset;
            offset.Y=World.Height(island,island.Center+p+new System.Numerics.Vector2(rotated.X,rotated.Z))-n.Position.Y;
            var props=new Node3D{Position=offset};n.AddChild(props);
            switch((i+island.Seed)%4)
            {
                case 0: Camp(props);break;
                case 1: Lookout(props);break;
                case 2: Cairn(props);break;
                default: Wreck(props);break;
            }
            lids.Add(Chest(n,new(0,.08f,0)));
        }
        return lids;
    }
    static void Camp(Node3D n)
    {
        var cloth=new SurfaceTool();cloth.Begin(Mesh.PrimitiveType.Triangles);
        Vector3[] points=[new(-2,0,-1.5f),new(0,2.2f,-1.5f),new(-2,0,1.5f),new(-2,0,1.5f),new(0,2.2f,-1.5f),new(0,2.2f,1.5f),new(0,2.2f,-1.5f),new(2,0,-1.5f),new(2,0,1.5f),new(0,2.2f,-1.5f),new(2,0,1.5f),new(0,2.2f,1.5f)];
        foreach(var p in points)cloth.AddVertex(p);cloth.GenerateNormals();n.AddChild(new MeshInstance3D{Mesh=cloth.Commit(),MaterialOverride=Art.Material(canvas)});
        foreach(float z in new[]{-1.5f,1.5f})Art.Cylinder(n,new(0,1.1f,z),.055f,2.2f,wood);
        for(int i=0;i<8;i++)Art.Source(n,"roundrock",new(MathF.Sin(i*Mathf.Tau/8)*.7f,0,3+MathF.Cos(i*Mathf.Tau/8)*.7f),.3f);
        Art.Cylinder(n,new(0,.3f,3),.26f,.4f,iron);
    }
    static void Lookout(Node3D n)
    {
        for(int i=0;i<3;i++)
        {
            var foot=new Vector3(MathF.Sin(i*Mathf.Tau/3)*.55f,0,MathF.Cos(i*Mathf.Tau/3)*.55f);var top=new Vector3(0,1.5f,0);
            var post=Art.Cylinder(n,(foot+top)*.5f,.05f,foot.DistanceTo(top),wood);post.Quaternion=new Quaternion(Vector3.Up,(top-foot).Normalized());
        }
        var tube=Art.Cylinder(n,new(0,1.65f,0),.15f,1.5f,iron);tube.Rotation=new(Mathf.Pi/2-.2f,0,0);
        Art.Cylinder(n,new(0,1.8f,.7f),.18f,.13f,Art.Gold).Rotation=new(Mathf.Pi/2-.2f,0,0);
        Art.Cylinder(n,new(0,1.816f,.766f),.14f,.014f,new("527e85")).Rotation=new(Mathf.Pi/2-.2f,0,0);
    }
    static void Cairn(Node3D n)
    {
        float y=0;for(int i=0;i<5;i++)
        {
            float height=1.15f-i*.17f;var stone=Art.Source(n,"roundrock",new((i%2)*.06f,y,0),height,i);
            stone.Scale*=new Vector3(1.4f,.38f,1.2f);y+=height*.33f;
        }
        Art.Cylinder(n,new(.15f,2.3f,0),.04f,1.7f,wood);
        var flag=Art.Mesh(n,new PlaneMesh{Size=new(.9f,.55f)},new(.55f,2.85f,0),new("994e39"));flag.Rotation=new(Mathf.Pi/2,0,0);

    }
    static void Wreck(Node3D n)
    {
        for(int i=0;i<7;i++){var rib=Art.Mesh(n,new TorusMesh{InnerRadius=1.3f,OuterRadius=1.42f,Rings=12,RingSegments=5},new(0,.03f,(i-3)*.5f),wood);rib.Rotation=new(Mathf.Pi/2,0,0);rib.Scale=new(1,.55f,1);}
        var mast=Art.Cylinder(n,new(1.4f,.35f,0),.10f,5,wood);mast.Rotation=new(0,0,1.42f);
    }
    static Node3D Chest(Node3D n,Vector3 p)
    {
        Art.Box(n,p+new Vector3(0,.28f,0),new(1.15f,.55f,.68f),wood);
        var hinge=new Node3D{Position=p+new Vector3(0,.55f,-.34f)};n.AddChild(hinge);
        var lid=Art.Cylinder(hinge,new(0,0,.34f),.34f,1.15f,wood);lid.Rotation=new(0,0,Mathf.Pi/2);lid.Scale=new(1,1,.8f);
        foreach(float x in new[]{-.42f,.42f})
        {
            Art.Box(n,p+new Vector3(x,.31f,.35f),new(.075f,.56f,.035f),iron);
            Art.Box(hinge,new(x,.15f,.34f),new(.075f,.065f,.68f),iron);
        }
        Art.Box(hinge,new(0,-.05f,.72f),new(.16f,.19f,.06f),Art.Gold);
        return hinge;
    }
}
