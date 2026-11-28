using Godot;

namespace BoatsNBeasts;

static class KeelwidowArt
{
    static readonly Color Plum = new("483957"), Iron = new("675268"), Vermilion = new("c74b44"),
        Flame = new("ef7350"), Cream = new("ffe5af"), Brass = new("d8a052"), Oak = new("9b633d");

    public static Node3D Make(bool mother)
    {
        var body = new ActorGeometry();
        float size = mother ? 1.30f : .82f;
        body.Sphere(new(0, .27f, .05f), new(1.12f, .34f, 1.16f), Plum);
        body.Sphere(new(0, .40f, -.02f), new(1.1f, .46f, 1.17f), Vermilion);
        for (int k = 0; k < 4; k++)
        {
            float z = -.80f + k * .48f;
            float width = MathF.Sqrt(1 - z * z * .52f);
            body.Tube([new(-width, .42f, z + .20f), new(-.56f, .72f, z), new(0, .88f, z - .15f), new(.56f, .72f, z), new(width, .42f, z + .20f)],
                [.03f, .075f, .085f, .075f, .03f], k % 2 == 0 ? Flame : new("b34a49"));
        }
        foreach (int side in new[] { -1, 1 })
        {
            for (int j = 0; j < 4; j++)
            {
                float z = -.52f + j * .40f;
                body.Tube([new(side * .78f, .37f, z), new(side * 1.19f, .50f, z + .06f), new(side * 1.43f, .25f, z + .28f), new(side * 1.49f, -.03f, z + .49f)],
                    [.122f, .15f, .082f, .015f], j % 2 == 1 ? Vermilion : Flame);
            }
            body.Tube([new(side * .68f, .39f, -.69f), new(side * 1.22f, .31f, -.84f), new(side * 1.37f, .49f, -1.22f)],
                [.19f, .16f, .24f], Vermilion);
            body.Tube([new(side * 1.35f, .49f, -1.18f), new(side * 1.45f, .62f, -1.55f), new(side * 1.28f, .75f, -1.85f)],
                [.26f, .18f, .018f], Flame);
            body.Tube([new(side * 1.26f, .50f, -1.18f), new(side * 1.07f, .44f, -1.46f), new(side * 1.12f, .50f, -1.70f)],
                [.17f, .105f, .012f], Vermilion);
            var eye = new Vector3(side * .52f, .61f, -.94f);
            body.Sphere(eye, new(.17f, .16f, .13f), Cream);
            body.Sphere(eye + new Vector3(0, -.013f, -.102f), new(.075f, .076f, .05f), Plum);
        }
        if (mother)
        {
            for (int k = 0; k < 5; k++)
            {
                float z = -.23f + k * .22f;
                body.Tube([new(-.74f, .99f, z), new(-.36f, .82f, z), new(.30f, .82f, z), new(.83f - k * .045f, 1.22f, z)],
                    [.064f, .075f, .075f, .055f], k % 2 == 1 ? new("d29763") : Oak, 5);
            }
            body.Tube([new(-.52f, .81f, .35f), new(-.44f, 1.19f, .70f), new(.30f, 1.58f, 1.06f)], [.09f, .072f, .032f], Oak);
            body.Tube([new(-.43f, 1.18f, .7f), new(.45f, 1.20f, .41f)], .045f, Oak);
            body.Polygon([new(-.34f, 1.22f, .65f), new(.43f, 1.23f, .41f), new(.30f, .97f, .50f), new(.19f, 1.06f, .56f), new(.07f, .91f, .57f)], new("dfbb81"), Vector3.Forward);
            body.Tube([new(-.8f, .90f, .5f), new(-.14f, 1.08f, -.15f), new(.93f, .58f, -.61f)], .042f, Cream);
            body.Tube([new(.82f, .65f, -.60f), new(.86f, .61f, -1.18f)], .095f, Brass);
            body.Sphere(new(.86f, .60f, -1.24f), new(.16f, .13f, .17f), Brass);
        }
        else
        {
            body.RoundBox(new(0, .83f, .24f), new(.70f, .41f, .65f), .032f, Oak);
            body.Tube([new(-.37f, .70f, .21f), new(-.35f, 1.06f, .21f), new(.35f, 1.06f, .21f), new(.38f, .70f, .21f)], .034f, Brass);
        }
        body.Scale(Vector3.One * size);
        var root = new Node3D();
        root.AddChild(new MeshInstance3D { Mesh = body.Mesh(DioramaSurface.Material) });
        root.AddChild(Foam(1.45f * size, 1.36f * size));
        return root;
    }

    static readonly Dictionary<(float,float),ArrayMesh> wakePrints=[];
    public static Node3D Foam(float width, float depth)
    {
        if(wakePrints.TryGetValue((width,depth),out var cached))
            return new MeshInstance3D {Mesh=cached,CastShadow=GeometryInstance3D.ShadowCastingSetting.Off};
        var foam = new ActorGeometry();
        Color wash=new("49a7a1"),mint=new("98d9c4"),ivory=new("f6e9be");
        void Stroke(float start,float sweep,float radius,float thick,float y,Color paint)
        {
            const int sections=17;
            Vector3 Point(float t,float side)
            {
                float a=start+t*sweep;
                float curl=.031f*MathF.Sin(7*a+.5f)+.020f*MathF.Sin(11*a+radius*3.2f);
                float brush=MathF.Pow(Math.Max(0,MathF.Sin(t*Mathf.Pi)),.68f);
                float edge=radius+curl+side*thick*brush*(.77f+.22f*MathF.Sin(4*a+start));
                return new(MathF.Cos(a)*width*edge, y, MathF.Sin(a)*depth*edge);
            }
            for(int j=0;j<sections;j++)
            {
                float t=j/(float)sections,u=(j+1f)/sections;
                foam.Polygon([Point(t,-1),Point(t,1),Point(u,1),Point(u,-1)],paint,Vector3.Up);
            }
        }
        float[] starts=[-.27f,1.22f,2.88f,4.36f,5.38f];
        float[] reaches=[1.07f,1.25f,1.04f,.76f,.42f];
        for(int i=0;i<starts.Length;i++)
        {
            float a=starts[i],span=reaches[i];
            Stroke(a-.14f,span+.19f,1.005f,.137f,.017f,wash);
            Stroke(a-.06f,span+.13f,1.015f,.083f,.024f,mint);
            Stroke(a,span,1.048f,.058f,.030f,ivory);
            Stroke(a+.22f,span*.48f,1.164f,.028f,.024f,mint);
            if(i%2==0)Stroke(a+.11f,span*.50f,1.184f,.020f,.031f,ivory);
        }
        wakePrints[(width,depth)]=cached=foam.Mesh(DioramaSurface.Material);
        return new MeshInstance3D { Mesh = cached, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
    }

    public static Node3D Buoy(bool repair)
    {
        var b = new ActorGeometry();
        b.Sphere(new(0, .09f, 0), new(.36f, .25f, .36f), Oak);
        b.Ring(new(0, .13f, 0), .35f, .04f, Brass);
        b.Tube([new(0, .18f, 0), new(0, .99f, 0)], .036f, Oak);
        b.Polygon([new(0, .96f, 0), new(.52f, .87f, 0), new(.35f, .77f, 0), new(.52f, .65f, 0), new(0, .72f, 0)], repair ? new("a3dfbc") : Flame, Vector3.Back);
        b.Sphere(new(0, 1.0f, 0), Vector3.One * .066f, Brass);
        var mesh = new MeshInstance3D { Mesh = b.Mesh(DioramaSurface.Material) };
        return mesh;
    }
}
