using Godot;
using WizNDragons.Core;
namespace WizNDragons;

// Three independently scrolling, deterministic layers. Only nearby cells exist in memory.
public partial class CloudLayers3D : Node3D
{
    readonly Dictionary<(int Layer,int X,int Y), Node3D> clouds = new();
    readonly Dictionary<int, ArrayMesh> meshes = new();
    readonly Dictionary<int, ShaderMaterial> materials = new();
    static readonly float[] Parallax = [.12f,.38f,.72f];
    static readonly float[] Height = [-13,-7,-2.5f];
    public int Count => clouds.Count;
    public void Reset() { foreach(var cloud in clouds.Values) cloud.QueueFree(); clouds.Clear(); }
    public void Sync(Vector2 camera,float clock,uint seed)
    {
        var keep=new HashSet<(int,int,int)>();
        for(int layer=0;layer<3;layer++)
        {
            float factor=Parallax[layer];
            var drift=new Vector2(clock*(layer+1)*1.8f,clock*(layer+1)*.6f);
            var layerCamera=camera*factor-drift;
            const float cell=1100;
            int cx=(int)Mathf.Floor(layerCamera.X/cell),cy=(int)Mathf.Floor(layerCamera.Y/cell);
            for(int y=cy-2;y<=cy+2;y++)for(int x=cx-2;x<=cx+2;x++)
            {
                var rng=new SeedRandom(SeedRandom.Hash(seed,x,y,(uint)(layer+100)));
                if(rng.Unit()>(layer==2?.24f:layer==1?.42f:.48f))continue;
                var key=(layer,x,y);keep.Add(key);
                var position=new Vector2(x*cell+rng.Range(100,1000),y*cell+rng.Range(100,1000));
                int variant=rng.Index(8);
                if(!clouds.TryGetValue(key,out var root))
                {
                    if(!meshes.TryGetValue(variant,out var mesh)) meshes[variant]=mesh=CloudArt3D.Build(variant);
                    if(!materials.TryGetValue(layer,out var material))
                    {
                        material=new ShaderMaterial { Shader=GD.Load<Shader>("res://source/presentation/cloud-surface.gdshader") };
                        material.SetShaderParameter("distance_haze",layer==0?.78f:layer==1?.48f:.08f);
                        materials[layer]=material;
                    }
                    root=new Node3D();root.AddChild(new MeshInstance3D { Mesh=mesh,MaterialOverride=material,CastShadow=GeometryInstance3D.ShadowCastingSetting.Off });
                    AddChild(root);clouds[key]=root;
                }
                var world=position+camera*(1-factor)+drift;
                root.Position=new(world.X*.01f,Height[layer],world.Y*.01f);
                root.Scale=Vector3.One*(layer==0?1.7f:layer==1?1.3f:1);
                root.Rotation=new(0,(variant-3)*.27f,0);
            }
        }
        foreach(var key in clouds.Keys.Where(k=>!keep.Contains(k)).ToArray()) { clouds[key].QueueFree();clouds.Remove(key); }
    }
}
