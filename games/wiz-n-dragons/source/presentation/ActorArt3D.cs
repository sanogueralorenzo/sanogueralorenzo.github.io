using Godot;
using WizNDragons.Core;
namespace WizNDragons;

// Original procedural miniatures; shared meshes keep actor rendering bounded.
public static class ActorArt3D
{
    static readonly Dictionary<string, ArrayMesh> Cache = new();
    static readonly Color Cream = new("ecd8a4"), Wood = new("98633b"), Gold = new("caa467"),
        Coral = new("d76b4b"), Eye = new("fff1c7"), Ink = new("192e31"), Purple = new("9358bd");
    public static void ResetCache() => Cache.Clear();
    static Node3D Instance(string key, Action<ActorGeometry> build)
    {
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var geometry = new ActorGeometry(); build(geometry); mesh = geometry.Mesh(DioramaSurface.Material); Cache[key] = mesh;
        }
        var root = new Node3D { Name = key };
        root.AddChild(new MeshInstance3D { Mesh = mesh, CastShadow = GeometryInstance3D.ShadowCastingSetting.On });
        return root;
    }
    public static Node3D Wizard(WizardKind kind, int[] spells) => Instance($"wizard-{kind}-{string.Join('-', spells)}", b =>
    {
        Color robe = kind == WizardKind.Ember ? new("975047") : kind == WizardKind.Warden ? new("448f91") : new("72538e");
        b.Tube([new(0,.2f,-.8f),new(0,.24f,.65f)],.045f,Wood);
        for (int i = -3; i <= 3; i++) b.Tube([new(i*.025f,.23f,.48f),new(i*.055f,.19f,.94f)],.038f,Gold);
        b.Sphere(new(0,.49f,0),new(.22f,.29f,.23f),robe);
        b.Polygon([new(-.18f,.6f,.1f),new(.18f,.6f,.1f),new(.32f,.23f,.5f),new(-.3f,.23f,.5f)],Cream,Vector3.Up);
        b.Sphere(new(0,.79f,-.1f),new(.14f,.16f,.14f),Cream);
        b.Sphere(new(0,.88f,-.075f),new(.37f,.055f,.32f),robe);
        b.Tube([new(0,.91f,-.06f),new(0,1.14f,-.02f),new(-.1f,1.32f,.06f),new(-.23f,1.3f,.1f)],[.21f,.13f,.065f,.008f],robe,10);
        b.Ring(new(0,.955f,-.055f),.185f,.027f,Gold);
        b.Tube([new(-.16f,.46f,0),new(-.25f,.15f,.03f),new(-.22f,.13f,-.2f)],.065f,Ink);
        b.Tube([new(.16f,.46f,0),new(.25f,.15f,.03f),new(.22f,.13f,-.2f)],.065f,Ink);
        b.Tube([new(.15f,.63f,-.05f),new(.32f,.51f,-.22f)],.065f,robe);
        b.Tube([new(.32f,.51f,-.22f),new(.36f,.64f,-.62f)],.025f,Wood);
        b.Crystal(new(.36f,.67f,-.65f),new(.065f,.12f,.065f),Purple);
        for (int i=0;i<spells.Length;i++) if(spells[i]>0)
        {
            float angle=i*Mathf.Tau/6;
            b.Crystal(new(Mathf.Cos(angle)*.43f,.5f,Mathf.Sin(angle)*.43f),new(.045f,.08f,.045f),Purple);
        }
        b.Scale(Vector3.One*1.25f);
    });
    public static Node3D Creature(EnemyKind kind) => Instance($"creature-{kind}", b =>
    {
        if (kind == EnemyKind.Spark)
        {
            b.Sphere(new(0,.23f,0),new(.24f,.25f,.22f),Gold);
            b.Tube([new(-.08f,.19f,.15f),new(.15f,.12f,.35f),new(-.12f,.08f,.48f),new(.05f,.03f,.66f)],.04f,Gold);
        }
        else
        {
            bool boss=kind==EnemyKind.ElderDragon;
            Color color=kind==EnemyKind.Wyrm?new("648caa"):kind==EnemyKind.Drake?new("8271a9"):Coral;
            b.Sphere(new(0,.27f,.04f),new(.23f,.28f,.36f),color);
            b.Sphere(new(0,.42f,-.29f),new(.28f,.25f,.25f),color);
            b.Sphere(new(0,.3f,-.47f),new(.2f,.1f,.16f),color.Lightened(.14f));
            b.Tube([new(0,.21f,.27f),new(.12f,.16f,.55f),new(.05f,.27f,.82f)],[.12f,.07f,.006f],color);
            for(int side=-1;side<=1;side+=2)
            {
                b.Polygon([new(side*.15f,.38f,.03f),new(side*.49f,.63f,-.17f),new(side*.8f,.34f,.08f),new(side*.48f,.22f,.14f),new(side*.25f,.18f,.3f)],color.Darkened(.15f),Vector3.Up);
                b.Tube([new(side*.17f,.58f,-.23f),new(side*.23f,.79f,-.13f)],[.07f,.008f],Cream);
                b.Sphere(new(side*.115f,.47f,-.49f),new(.085f,.09f,.04f),Eye);
                b.Sphere(new(side*.115f,.47f,-.524f),new(.035f,.049f,.019f),Ink);
            }
            if(boss)b.Scale(Vector3.One*2.65f);
        }
        if(kind==EnemyKind.Spark)for(int side=-1;side<=1;side+=2)
        {
            b.Sphere(new(side*.09f,.3f,-.2f),new(.065f,.07f,.035f),Eye);
            b.Sphere(new(side*.09f,.3f,-.23f),new(.028f,.04f,.012f),Ink);
        }
    });
    public static void Animate(Node3D root, float clock, float speed)
    {
        var mesh=root.GetChild<Node3D>(0);
        mesh.Position=new(0,Mathf.Sin(clock*2.5f)*.055f,0);
        mesh.Rotation=new(Mathf.Sin(clock*2)*.025f,0,Mathf.Sin(clock*2.7f)*.04f);
    }
    public static void AnimateWizard(Node3D root,float clock,float speed,float aim) => Animate(root,clock,speed);
}
