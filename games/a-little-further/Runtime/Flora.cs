using Godot;
using Further.Core;
using Further.Salvage;
namespace Further;

// The actual Seabreeze canopy, branching and rasterized leaf recipes are retained.
public static class Flora
{
    static readonly SeabreezePlantMeshes plants=new(new SeabreezeRandom());
    static readonly Dictionary<int,SeabreezePlantMeshes.Plant> trees=[];
    static readonly Dictionary<int,ShaderMaterial> leaves=[];
    static readonly Dictionary<int,SeabreezePlantMeshes.Plant> bushes=[];
    static readonly Material bark=SeabreezeTextures.BarkMaterial();
    static Texture2D? texture;
    static ArrayMesh? grass;
    static ShaderMaterial? grassMaterial;
    static ShaderMaterial Leaves(int biome)
    {
        if(leaves.TryGetValue(biome,out var value))return value;
        texture??=SeabreezeTextures.LeafTexture(23);
        value=new(){Shader=GD.Load<Shader>("res://Shaders/foliage.gdshader")};
        value.SetShaderParameter("leaf_texture",texture);
        value.SetShaderParameter("tint",new Color(biome switch{1=>"527967",2=>"839448",_=>"497645"}));
        value.SetShaderParameter("wind_amplitude",.13f);leaves[biome]=value;return value;
    }
    static MultiMeshInstance3D? Batch(Node3D parent,Mesh mesh,Material material,List<Transform3D> placements)
    {
        if(placements.Count==0)return null;
        var instances=new MultiMesh{TransformFormat=MultiMesh.TransformFormatEnum.Transform3D,Mesh=mesh,InstanceCount=placements.Count};
        for(int i=0;i<placements.Count;i++)instances.SetInstanceTransform(i,placements[i]);
        var node=new MultiMeshInstance3D{Multimesh=instances,MaterialOverride=material};parent.AddChild(node);return node;
    }
    public static void Build(Node3D parent,Island island,IReadOnlyList<Decoration> scenery)
    {
        for(int variant=0;variant<4;variant++)
        {
            if(!trees.TryGetValue(variant,out var tree)){tree=plants.TreeMesh(variant+1,variant==2);trees[variant]=tree;}
            var placements=new List<Transform3D>();
            for(int i=0;i<scenery.Count;i++)
            {
                var d=scenery[i];if(d.Asset!="tree"||i%4!=variant)continue;
                placements.Add(new(new Basis(Vector3.Up,d.Yaw).Scaled(Vector3.One*(d.Height/10)),Art.At(d.LocalPosition,d.Ground)));
            }
            Batch(parent,tree.Trunk!,bark,placements);
            var canopy=Batch(parent,tree.Leaves,Leaves(island.Biome),placements);
            if(canopy!=null){canopy.VisibilityRangeEnd=240;canopy.VisibilityRangeEndMargin=30;canopy.VisibilityRangeFadeMode=GeometryInstance3D.VisibilityRangeFadeModeEnum.Self;}
            // Preserve crown silhouettes when fine alpha-tested leaves become subpixel.
            var bounds=tree.Leaves.GetAabb();using var silhouette=new SurfaceTool();silhouette.Begin(Mesh.PrimitiveType.Triangles);
            var sphere=new SphereMesh{Radius=1,Height=2,RadialSegments=12,Rings=6};
            silhouette.AppendFrom(sphere,0,new Transform3D(Basis.Identity.Scaled(bounds.Size*.43f),bounds.GetCenter()));
            var distant=Batch(parent,silhouette.Commit(),Art.Material(new Color(island.Biome switch{1=>"527967",2=>"839448",_=>"497645"})),placements);
            if(distant!=null){distant.VisibilityRangeBegin=200;distant.VisibilityRangeBeginMargin=30;distant.VisibilityRangeFadeMode=GeometryInstance3D.VisibilityRangeFadeModeEnum.Self;distant.CastShadow=GeometryInstance3D.ShadowCastingSetting.Off;}
        }
    }
    public static void Shrubs(Node3D parent,Island island,IReadOnlyList<Decoration> scenery)
    {
        for(int variant=0;variant<3;variant++)
        {
            if(!bushes.TryGetValue(variant,out var bush)){bush=plants.BushMesh(variant);bushes[variant]=bush;}
            var bounds=bush.Leaves.GetAabb();var placements=new List<Transform3D>();
            for(int i=0;i<scenery.Count;i++)
            {
                var d=scenery[i];if(d.Asset!="bush"||i%3!=variant)continue;float scale=d.Height/bounds.Size.Y;
                placements.Add(new(new Basis(Vector3.Up,d.Yaw).Scaled(Vector3.One*scale),Art.At(d.LocalPosition,d.Ground-bounds.Position.Y*scale)));
            }
            var node=Batch(parent,bush.Leaves,Leaves(island.Biome),placements);
            if(node!=null){node.VisibilityRangeEnd=130;node.VisibilityRangeEndMargin=20;node.VisibilityRangeFadeMode=GeometryInstance3D.VisibilityRangeFadeModeEnum.Self;}
        }
    }
    public static void Groundcover(Node3D parent,IReadOnlyList<MeadowTuft> meadow)
    {
        grass??=plants.GrassMesh();grassMaterial??=new ShaderMaterial{Shader=GD.Load<Shader>("res://Shaders/grass.gdshader")};
        var patches=new Dictionary<(int,int),List<Transform3D>>();
        foreach(var tuft in meadow)
        {
            var p=tuft.Position;var key=((int)MathF.Floor(p.X/24),(int)MathF.Floor(p.Y/24));
            if(!patches.TryGetValue(key,out var items))patches[key]=items=[];
            items.Add(new(new Basis(Vector3.Up,tuft.Yaw).Scaled(new(1,tuft.Scale,1)),new(p.X-key.Item1*24,tuft.Ground,p.Y-key.Item2*24)));
        }
        foreach(var (key,placements) in patches)
        {
            var node=new Node3D{Position=new(key.Item1*24,0,key.Item2*24)};parent.AddChild(node);Batch(node,grass,grassMaterial,placements);
            foreach(var child in node.GetChildren().OfType<MultiMeshInstance3D>()){child.VisibilityRangeEnd=85;child.VisibilityRangeEndMargin=15;child.VisibilityRangeFadeMode=GeometryInstance3D.VisibilityRangeFadeModeEnum.Self;child.CastShadow=GeometryInstance3D.ShadowCastingSetting.Off;}
        }
    }
    public static void Update(Vector3 captain,Vector3 camera)
    {
        foreach(var material in leaves.Values){material.SetShaderParameter("cat_position",captain);material.SetShaderParameter("camera_position",camera);}
        grassMaterial?.SetShaderParameter("cat_position",captain);
    }

}
