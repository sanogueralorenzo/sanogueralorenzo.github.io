using Godot;

namespace BoatsNBeasts;

static class LanternCargo
{
    static readonly Color Wood = new("995e3c"), Honey = new("e5ad6c"), Pitch = new("50384a"), Ivory = new("ffe4ae"), Teal = new("368f87"), Red = new("e45543");
    static readonly Dictionary<string, ArrayMesh> meshes = [];

    public static MeshInstance3D Make(string kind)
    {
        if (!meshes.TryGetValue(kind, out var mesh))
        {
            var b = new ActorGeometry();
            switch (kind)
            {
                case "tender":
                    Skiff(b);
                    b.RoundBox(new(0, .27f, .21f), new(.88f, .09f, .36f), .025f, Honey);
                    b.Tube([new(0, .20f, -.4f), new(0, 1.35f, -.4f)], .038f, Wood);
                    b.Polygon([new(0, 1.33f, -.4f), new(.65f, .58f, -.35f), new(.04f, .50f, -.21f)], Ivory, Vector3.Back);
                    Person(b, new(-.15f, .27f, .23f), Teal);
                    break;
                case "lifeboat":
                    Skiff(b);
                    Person(b, new(0, .2f, 0), Teal);
                    b.Scale(Vector3.One * .70f);
                    break;
                case "swivel":
                    b.RoundBox(new(0, .12f, 0), new(.71f, .24f, .76f), .06f, Wood);
                    b.Sphere(new(0, .36f, 0), new(.23f, .22f, .23f), Honey);
                    b.Tube([new(0, .37f, .10f), new(0, .55f, -.50f)], [.14f, .12f], Pitch);
                    b.Sphere(new(0, .55f, -.50f), new(.132f, .125f, .044f), Red);
                    break;
                case "castaway":
                    b.Ring(new(0, .09f, 0), .29f, .09f, Honey);
                    Person(b, new(0, -.05f, 0), Teal);
                    b.Tube([new(.07f, .26f, 0), new(.18f, .42f, 0), new(.23f, .50f, 0)], .035f, Ivory);
                    break;
                case "powder":
                    b.RoundBox(new(0, .07f, 0), new(.84f, .13f, .96f), .04f, Wood);
                    for (int i = -1; i <= 1; i += 2)
                    {
                        b.Sphere(new(i * .19f, .28f, 0), new(.16f, .24f, .18f), Honey);
                        b.Ring(new(i * .19f, .31f, 0), .16f, .025f, Pitch);
                    }
                    break;
                case "tongue":
                    b.Tube([new(-.14f, .25f, .31f), new(.12f, .30f, -.34f)], [.10f, .13f], Honey);
                    b.Sphere(new(.13f, .33f, -.37f), new(.24f, .22f, .22f), new("f1b960"));
                    b.Tube([new(-.44f, .04f, -.56f), new(.27f, .04f, .56f)], .12f, Wood);
                    b.Tube([new(-.55f, .03f, -.25f), new(.06f, .03f, .63f)], .095f, Wood);
                    break;
                case "purse":
                    b.RoundBox(new(0, .08f, 0), new(.46f, .14f, .41f), .04f, Wood);
                    b.Sphere(new(0, .20f, 0), new(.16f, .18f, .16f), Honey);
                    b.Ring(new(0, .33f, 0), .12f, .025f, Ivory);
                    break;
                default:
                    b.Sphere(new(0, .13f, 0), new(.27f, .29f, .27f), Red);
                    b.Ring(new(0, .16f, 0), .267f, .034f, Pitch);
                    b.Tube([new(0, .33f, 0), new(0, .56f, .07f)], .036f, Honey);
                    b.Sphere(new(0, .56f, .07f), Vector3.One * .072f, Ivory);
                    break;
            }
            meshes[kind] = mesh = b.Mesh(DioramaSurface.Material);
        }
        return new MeshInstance3D { Mesh = mesh };
    }

    static void Skiff(ActorGeometry b)
    {
        Vector3[] Ring(float width, float length, float height) =>
        [
            new(0,height+.10f,-length),new(width*.79f,height,-length*.54f),
            new(width,height,length*.29f),new(width*.68f,height+.035f,length*.79f),
            new(-width*.68f,height+.035f,length*.79f),new(-width,height,length*.29f),
            new(-width*.79f,height,-length*.54f)
        ];
        b.Loft([Ring(.12f, .89f, -.05f), Ring(.51f, 1.08f, .22f), Ring(.53f, 1.09f, .27f)], [Teal, Honey]);
        b.Polygon(Ring(.49f, 1.03f, .19f), Wood, Vector3.Up);
    }

    static void Person(ActorGeometry b, Vector3 p, Color coat)
    {
        b.Sphere(p + new Vector3(0, .18f, 0), new(.12f, .18f, .08f), coat);
        b.Sphere(p + new Vector3(0, .39f, 0), new(.085f, .095f, .08f), Honey);
        b.Sphere(p + new Vector3(0, .45f, .006f), new(.12f, .05f, .105f), Pitch);
    }
}
