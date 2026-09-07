using Godot;
using Further.Core;
using V2=System.Numerics.Vector2;
namespace Further;
public sealed class IslandView
{
    public required Island Island;
    public required Node3D Root;
    public readonly List<MeshInstance3D> Coins=[];
    public Node3D? Bell;
    public bool Detailed;
    public readonly List<MeshInstance3D> Foliage=[];
}
public sealed class Islands(Node3D parent,Run run)
{
    public readonly Dictionary<Cell,IslandView> Loaded=[];
    public int Builds,Evictions;
    static ShaderMaterial? terrainMaterial;
    Cell? lastCell;
    Queue<Cell> pending=[];
    public void Step(Camera3D camera)
    {
        Cell cell=run.World.CellAt(run.Position);
        if(cell!=lastCell)
        {
            lastCell=cell;var desired=run.World.Visible(run.Position,PrivateSources.NeighborRadius(420,World.ChunkSize)).ToHashSet();
            foreach(var key in Loaded.Keys.Where(k=>!desired.Contains(k)).ToArray()){Loaded[key].Root.QueueFree();Loaded.Remove(key);Evictions++;}
            pending=new(run.World.Visible(run.Position,2).Where(c=>!Loaded.ContainsKey(c)));
        }
        if(pending.TryDequeue(out var next)){Build(next);Builds++;}
        else
        {
            var upgrade=Loaded.Values.FirstOrDefault(v=>!v.Detailed && V2.Distance(v.Island.Center,run.Position)<210);
            if(upgrade!=null){upgrade.Root.QueueFree();Build(upgrade.Island.Cell);Builds++;}
        }
        foreach(var view in Loaded.Values)
        {
            foreach(var tree in view.Foliage)
            {
                Vector3 start=camera.GlobalPosition,end=Art.At(run.Position,run.Height+1),line=end-start;
                float t=Math.Clamp((tree.GlobalPosition-start).Dot(line)/line.LengthSquared(),0,1);
                float gap=(start+line*t).DistanceTo(tree.GlobalPosition+Vector3.Up*tree.Scale.Y*.45f);
                tree.Transparency=gap<tree.Scale.Y*.8f && t>.15f?.86f:0;
            }
            for(int i=0;i<view.Coins.Count;i++){var coin=view.Coins[i];coin.Visible=!run.Treasure.Contains((view.Island.Cell,i));coin.Rotation=new(.25f,(float)run.Time*1.8f+i,0);}
        }
    }
    public void Shift()
    {
        foreach(var view in Loaded.Values){view.Island=run.World.IslandAt(view.Island.Cell);view.Root.Position=Art.At(view.Island.Center,0);}
        lastCell=null;
    }
    void Build(Cell c)
    {
        Island island=run.World.IslandAt(c);var root=new Node3D{Name=island.Name,Position=Art.At(island.Center,0)};parent.AddChild(root);
        var view=new IslandView{Island=island,Root=root};Loaded[c]=view;
        bool near=V2.Distance(island.Center,run.Position)<240;
        int count=near?65:25;float extent=island.Radius*2.65f,step=extent/(count-1);
        var grid=PrivateSources.BorderedGrid(count,step,(x,z)=>World.Height(island,island.Center+new V2(x,z)));
        var st=new SurfaceTool();st.Begin(Godot.Mesh.PrimitiveType.Triangles);
        void Vertex(int x,int z)
        {
            var p=grid[(z+1)*(count+2)+x+1];float y=p.Y;float pathX=MathF.Sin(p.Z*.07f)*island.Radius*.19f;
            Color grass=island.Biome switch{0=>new("5c894d"),1=>new("829778"),_=>new("b09b61")};
            Color color=y<.5f?new("bdc29b"):y<2.4f?new("c5ac76"):grass;
            if(y>2.4f && MathF.Abs(p.X-pathX)<2.7f && p.Z<island.Radius*.4f)color=new("c9b783");
            color=color.Darkened((float)(World.Hash(x,z,island.Seed)%100)*.0007f);
            var left=grid[(z+1)*(count+2)+x];var right=grid[(z+1)*(count+2)+x+2];var back=grid[z*(count+2)+x+1];var front=grid[(z+2)*(count+2)+x+1];
            st.SetColor(color);st.SetNormal(new Vector3(left.Y-right.Y,2*step,back.Y-front.Y).Normalized());st.AddVertex(new(p.X,p.Y,p.Z));
        }
        for(int z=0;z<count-1;z++)for(int x=0;x<count-1;x++){Vertex(x,z);Vertex(x+1,z);Vertex(x,z+1);Vertex(x+1,z);Vertex(x+1,z+1);Vertex(x,z+1);}
        var mesh=st.Commit();
        if(terrainMaterial==null)
        {
            terrainMaterial=new ShaderMaterial{Shader=GD.Load<Shader>("res://Shaders/terrain.gdshader")};
            terrainMaterial.SetShaderParameter("grass_texture",ImageTexture.CreateFromImage(Image.LoadFromFile(Art.Local("hike/Grass.png"))));
        }
        var material=terrainMaterial;
        root.AddChild(new MeshInstance3D{Mesh=mesh,MaterialOverride=material});
        view.Detailed=near;
        if(!near)return;
        foreach(var decoration in IslandLayout.Scenery(island))
        {
            var scenery=Art.Source(root,decoration.Asset,Art.At(decoration.LocalPosition,decoration.Ground),decoration.Height,decoration.Yaw);
            if(decoration.Asset is "palm" or "pine" or "birch")view.Foliage.Add(scenery);
        }
        V2 landing=island.Landing-island.Center;float lh=World.Height(island,island.Landing);
        for(int k=0;k<7;k++)Art.Box(root,Art.At(landing+new V2(0,-k*.85f),MathF.Max(.45f,lh)),new(3,.18f,.72f),new("9e7650"));
        Art.Cylinder(root,Art.At(landing+new V2(2,0),lh+1.7f),.12f,3.4f,Art.Ink);
        Art.Sphere(root,Art.At(landing+new V2(2,0),lh+3.3f),.32f,Art.Gold).MaterialOverride=Art.Material(Art.Gold,true);
        view.Bell=Art.Shrine(root,Art.At(island.Shrine-island.Center,World.Height(island,island.Shrine)));
        for(int k=0;k<8;k++)
        {
            V2 p=IslandLayout.Treasure(island,k)-island.Center;
            var coin=Art.Mesh(root,new CylinderMesh{TopRadius=.38f,BottomRadius=.38f,Height=.13f,RadialSegments=10},Art.At(p,World.Height(island,island.Center+p)+.8f),Art.Gold);
            coin.MaterialOverride=Art.Material(Art.Gold,true);view.Coins.Add(coin);
        }
    }
}
