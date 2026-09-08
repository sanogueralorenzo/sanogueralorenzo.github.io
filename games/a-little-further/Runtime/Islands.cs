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
    public readonly List<Node3D> CacheLids=[];
}
public sealed class Islands(Node3D parent,Run run)
{
    public readonly Dictionary<Cell,IslandView> Loaded=[];
    public int Builds,Evictions;
    public double LastBuildMs;
    static ShaderMaterial? terrainMaterial;
    Cell? lastCell;
    Queue<Cell> pending=[];
    HashSet<Cell> desired=[];
    Task<TerrainMeshData>? generation;
    Cell generatingCell;
    bool generatingDetailed;
    const float DetailDistance=World.SightDistance+260;
    public void Step(Camera3D camera)
    {
        Cell cell=run.World.CellAt(run.Position);
        if(cell!=lastCell)
        {
            lastCell=cell;desired=run.World.Visible(run.Position,PrivateSources.NeighborRadius(4500,World.ChunkSize)).ToHashSet();
            foreach(var key in Loaded.Keys.Where(k=>!desired.Contains(k)).ToArray()){Loaded[key].Root.QueueFree();Loaded.Remove(key);Evictions++;}
            pending=new(run.World.Visible(run.Position,1).Where(c=>!Loaded.ContainsKey(c)));
        }
        if(generation is {IsCompleted:true})
        {
            var data=generation.GetAwaiter().GetResult();
            if(desired.Contains(generatingCell))
            {
                if(Loaded.TryGetValue(generatingCell,out var old))old.Root.QueueFree();
                ulong start=Godot.Time.GetTicksUsec();Build(generatingCell,generatingDetailed,data);Builds++;LastBuildMs=(Godot.Time.GetTicksUsec()-start)/1000.0;
            }
            generation=null;
        }
        if(generation==null)
        {
            Cell? next=null;while(pending.TryDequeue(out var queued)){if(!Loaded.ContainsKey(queued)){next=queued;break;}}
            next??=Loaded.Values.FirstOrDefault(v=>!v.Detailed && V2.Distance(v.Island.Center,run.Position)<DetailDistance)?.Island.Cell;
            if(next is Cell target)
            {
                var island=run.World.IslandAt(target);generatingCell=target;generatingDetailed=V2.Distance(island.Center,run.Position)<DetailDistance;
                bool detail=generatingDetailed;generation=Task.Run(()=>TerrainMeshData.Generate(island,detail));
            }
        }
        foreach(var view in Loaded.Values)
        {
            view.Root.Visible=run.World.InSight(view.Island,run.Position);
            if(view.Bell!=null)
            {
                bool ringing=run.Current?.Cell==view.Island.Cell && run.ShrineSeconds>0;
                view.Bell.GetNode<Node3D>("Bell").Rotation=new(0,0,ringing?MathF.Sin((float)run.Time*3.4f)*.19f:0);
                view.Bell.GetNode<OmniLight3D>("Lantern").LightEnergy=run.Claimed.Contains(view.Island.Cell)?.1f:.65f;
            }
            for(int i=0;i<view.CacheLids.Count;i++)view.CacheLids[i].Rotation=new(run.Treasure.Contains((view.Island.Cell,i+8))?-1.8f:0,0,0);
            for(int i=0;i<view.Coins.Count;i++){var coin=view.Coins[i];coin.Visible=i<8 && !run.Treasure.Contains((view.Island.Cell,i));coin.Rotation=new(.25f,(float)run.Time*1.8f+i,0);}
        }
    }
    public void Shift()
    {
        foreach(var view in Loaded.Values){view.Island=run.World.IslandAt(view.Island.Cell);view.Root.Position=Art.At(view.Island.Center,0);}
        lastCell=null;
    }
    void Build(Cell c,bool near,TerrainMeshData data)
    {
        Island island=run.World.IslandAt(c);var root=new Node3D{Name=island.Name,Position=Art.At(island.Center,0)};parent.AddChild(root);
        var view=new IslandView{Island=island,Root=root};Loaded[c]=view;
        var positions=data.Positions.Select(v=>new Vector3(v.X,v.Y,v.Z)).ToArray();
        var normals=data.Normals.Select(v=>new Vector3(v.X,v.Y,v.Z)).ToArray();
        var colors=new Color[positions.Length];
        for(int i=0;i<colors.Length;i++)
        {
            float y=positions[i].Y;
            Color grass=island.Biome switch{0=>new("5c794c"),1=>new("667b69"),_=>new("8a8556")};
            colors[i]=y<.5f?new("bdc29b"):y<2.4f?new("baa67c"):data.Trail[i]<1.6f?new("a99a76"):grass;
        }
        var arrays=new Godot.Collections.Array();arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex]=positions;arrays[(int)Mesh.ArrayType.Normal]=normals;arrays[(int)Mesh.ArrayType.Color]=colors;arrays[(int)Mesh.ArrayType.Index]=data.Indices;
        var mesh=new ArrayMesh();mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles,arrays);
        if(terrainMaterial==null)
        {
            terrainMaterial=new ShaderMaterial{Shader=GD.Load<Shader>("res://Shaders/terrain.gdshader")};
            terrainMaterial.SetShaderParameter("grass_texture",ImageTexture.CreateFromImage(Image.LoadFromFile(Art.Local("hike/Grass.png"))));
        }
        var material=terrainMaterial;
        root.AddChild(new MeshInstance3D{Mesh=mesh,MaterialOverride=material});
        view.Detailed=near;
        if(!near)return;
        var layout=data.Scenery;Flora.Build(root,island,layout);Flora.Shrubs(root,island,layout);Flora.Groundcover(root,data.Meadow);
        foreach(var decoration in layout.Where(d=>d.Asset is not ("tree" or "bush")))
        {
            var scenery=Art.Source(root,decoration.Asset,Art.At(decoration.LocalPosition,decoration.Ground),decoration.Height,decoration.Yaw);

        }
        V2 landing=island.Landing-island.Center;float lh=World.Height(island,island.Landing);
        for(int k=0;k<7;k++)Art.Box(root,Art.At(landing+new V2(0,-k*.85f),MathF.Max(.45f,lh)),new(3,.18f,.72f),new("9e7650"));
        Art.Cylinder(root,Art.At(landing+new V2(2,0),lh+1.7f),.12f,3.4f,Art.Ink);
        Art.Sphere(root,Art.At(landing+new V2(2,0),lh+3.3f),.32f,Art.Gold).MaterialOverride=Art.Material(Art.Gold,true);
        view.CacheLids.AddRange(Discoveries.Build(root,island));
        view.Bell=Art.Shrine(root,Art.At(island.Shrine-island.Center,World.Height(island,island.Shrine)));
        for(int k=0;k<IslandLayout.TreasureCount;k++)
        {
            V2 p=IslandLayout.Treasure(island,k)-island.Center;
            var coin=Art.Mesh(root,new CylinderMesh{TopRadius=.38f,BottomRadius=.38f,Height=.13f,RadialSegments=10},Art.At(p,World.Height(island,island.Center+p)+.8f),Art.Gold);
            coin.MaterialOverride=Art.Material(Art.Gold,true);view.Coins.Add(coin);
        }
    }
}
