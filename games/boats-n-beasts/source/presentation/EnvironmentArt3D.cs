using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

/// <summary>Seeded, flat-shaded diorama scenery. One world unit is 100 simulation units.</summary>
public static class EnvironmentArt3D
{
    private static readonly Color Sand = new("ebcd8e"), Stone = new("64747b"), Leaf = new("6f8f46");
    private static readonly Dictionary<string, Material> Materials = new();

    public static Node3D Build(Place place)
    {
        var art = new Sculptor();
        var rng = new SeedRandom(place.Style);
        float r = place.Radius * .01f;
        if (place.Kind == PlaceKind.Rock)
        {
            Land(art, r * .88f, place.Style, true);
            Rock(art, new(0, .04f, 0), new(r * 1.7f, r * 1.65f, r * 1.5f), place.Style);
            Rock(art, new(-r * .48f, .01f, r * .5f), new(r * .8f, r * .65f, r * .7f), place.Style + 21);
        }
        else if (place.Kind is PlaceKind.Harbor or PlaceKind.Island)
        {
            Land(art, r, place.Style, false);
            if (place.Kind == PlaceKind.Harbor)
            {
                AddCottage(art, new(-r * .17f, .15f, -r * .10f), r * .76f, -.20f);
                Dock(art, r);
                Palm(art, new(-r * .60f, .17f, -r * .16f), r * .68f, place.Style);
                Palm(art, new(r * .38f, .18f, -r * .48f), r * .76f, place.Style + 33);
                Rock(art, new(-r * .53f, .09f, r * .53f), new(r * .47f, r * .31f, r * .39f), place.Style + 2);
                Rock(art, new(r * .38f, .12f, -r * .34f), new(r * .56f, r * .76f, r * .54f), place.Style + 9);
                Barrel(art, new(r * .35f, .18f, r * .32f), r * .16f);
                Barrel(art, new(r * .55f, .16f, r * .25f), r * .13f);
            }
            else
            {
                // Off-centre, overlapping shoulders form a cliff silhouette, not a symmetric stack.
                Rock(art, new(-r * .13f, .14f, -r * .22f), new(r * .90f, r * 2.05f, r * .78f), place.Style);
                Rock(art, new(r * .20f, .13f, -r * .04f), new(r * .70f, r * .91f, r * .67f), place.Style + 13);
                Rock(art, new(-r * .36f, .12f, r * .06f), new(r * .52f, r * .57f, r * .63f), place.Style + 31);
                Palm(art, new(r * .51f, .14f, r * .0f), r * .84f, place.Style + 1);
                Palm(art, new(-r * .12f, .17f, r * .46f), r * .64f, place.Style + 2);
                Rock(art, new(r * .52f, .08f, r * .52f), new(r * .38f, r * .25f, r * .31f), place.Style + 3);
            }
            for (int i = 0; i < 5; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.4f, .7f) * r;
                var at = new Vector3(Mathf.Cos(angle) * reach, .13f, Mathf.Sin(angle) * reach);
                if (place.Kind == PlaceKind.Harbor && at.Z > -.05f && at.X > -.4f * r) continue;
                Shrub(art, at, rng.Range(.17f, .25f) * r, rng.Next());
            }
        }
        return art.Finish("Environment_" + place.Kind);
    }

    /// <summary>A unit-scale cottage rooted at its floor, for the native style sample.</summary>
    public static Node3D Cottage()
    {
        var art = new Sculptor();
        AddCottage(art, Vector3.Zero, 1, -.20f);
        return art.Finish("Cottage");
    }

    private static float Coast(float a, uint seed) => 1 + .040f * Mathf.Sin(a * 2 + seed % 17) + .025f * Mathf.Cos(a * 3 + seed % 11);

    private static void Land(Sculptor art, float r, uint seed, bool rock)
    {
        const int sides = 96;
        float[] radii = [0, .72f, .94f, 1.04f, 1.16f, 1.42f];
        float[] heights = [.18f, .18f, .09f, .025f, .009f, .006f];
        Color[] colors = [Sand, Sand, new("f3daa4"), new("f8e5b5"), new("2ca4a8"), new("188695")];
        if (rock) { heights = [.06f, .05f, .024f, .014f, .009f, .006f]; colors[1] = colors[2] = colors[3] = new("2ca4a8"); }
        // Sand and both shallow-water bands share one smooth, rounded contour.
        Vector3 Point(int layer, int i)
        {
            float a = i * Mathf.Tau / sides;
            float radius = radii[layer] * Coast(a, seed);
            return new(Mathf.Cos(a) * radius * r, heights[layer], Mathf.Sin(a) * radius * r);
        }
        for (int layer = 0; layer < radii.Length - 1; layer++)
            for (int i = 0; i < sides; i++)
            {
                var a=Point(layer,i); var b=Point(layer,i+1); var c=Point(layer+1,i+1); var d=Point(layer+1,i);
                var color=colors[layer+1]; string surface=layer>=3?"shelf":"matte";
                art.Triangle(a,b,d,color,color,color,Vector3.Up,Vector3.Up,Vector3.Up,surface);
                art.Triangle(b,c,d,color,color,color,Vector3.Up,Vector3.Up,Vector3.Up,surface);
            }
        // A few smooth ivory arcs; most of the shoreline stays quiet.
        for (int patch=0;patch<(rock?1:3);patch++)
        {
            float start=patch*Mathf.Tau/3+seed%11, span=rock?.38f:.70f;
            for(int i=0;i<10;i++)
            {
                float a=start+span*i/10, b=start+span*(i+1)/10;
                float width=r*.019f*Mathf.Sin((i+.5f)*Mathf.Pi/10);
                Vector3 P(float t,float offset)=>new(Mathf.Cos(t)*(r*1.065f*Coast(t,seed)+offset),.03f,Mathf.Sin(t)*(r*1.065f*Coast(t,seed)+offset));
                art.Quad(P(a,0),P(b,0),P(b,width),P(a,width),new("bddbd0"));
            }
        }
    }

    private static void Rock(Sculptor art, Vector3 at, Vector3 size, uint seed)
    {
        var rng = new SeedRandom(seed);
        Color color = Stone.Lightened((seed % 9) * .012f);
        var old = art.Transform;
        art.Transform *= new Transform3D(Basis.FromEuler(new(0, rng.Range(-.55f, .55f), 0)), at);
        art.Boulder(new(0, size.Y * .48f, 0), size, color, seed);
        art.Transform = old;
    }

    private static void AddCottage(Sculptor art, Vector3 origin, float scale, float yaw)
    {
        // Local transform keeps all cottage details in the same merged material surface.
        var old = art.Transform;
        art.Transform = new Transform3D(Basis.FromEuler(new(0, yaw, 0)).Scaled(Vector3.One * scale), origin);
        Color plaster = new("d4ccad"), trim = new("ece0b7"), wood = new("795538"), roof = new("b8683d"), glass = new("274853");
        art.RoundedBox(new(0, .37f, 0), new(.88f, .74f, .72f), .065f, plaster);
        art.RoundedBox(new(0, .04f, 0), new(.99f, .13f, .81f), .04f, new("aaa68c"));
        // Gable faces under the roof remain full three-dimensional wall geometry.
        art.Face(new(-.45f, .73f, .36f), new(.45f, .73f, .36f), new(0, 1.09f, .36f), plaster);
        art.Face(new(.45f, .73f, -.36f), new(-.45f, .73f, -.36f), new(0, 1.09f, -.36f), plaster);
        for (int side = -1; side <= 1; side += 2)
        {
            float z=side*.47f;
            art.Quad(new(0,1.13f,z),new(side*.56f,.73f,z),new(side*.56f,.73f,-z),new(0,1.13f,-z),roof);
            art.Tube(new(side*.56f,.72f,-.48f),new(side*.56f,.72f,.48f),.025f,.025f,roof.Darkened(.12f),4);
        }
        art.Tube(new(0,1.13f,-.48f),new(0,1.13f,.48f),.03f,.03f,roof.Lightened(.08f),4);
        art.RoundedBox(new(-.26f, 1.11f, -.22f), new(.16f, .50f, .18f), .025f, new("b6a489"));
        art.RoundedBox(new(-.26f, 1.365f, -.22f), new(.205f, .075f, .23f), .022f, trim);
        art.RoundedBox(new(-.26f, 1.406f, -.22f), new(.09f, .009f, .11f), .006f, new("49483d"));
        Arch(art, new(.12f, .08f, .367f), .285f, .47f, .055f, new("45616a"), trim);
        art.Ellipsoid(new(.17f, .27f, .415f), new(.012f, .012f, .012f), new("c7aa62"), 8, 5);
        Window(art, new(-.235f, .47f, .378f), .16f, .22f, glass, trim);
        Window(art, new(0, .87f, .375f), .115f, .13f, glass, trim);
        // Side window is rotated with the wall, with inset glass and raised timber trim.
        var houseTransform = art.Transform;
        art.Transform = houseTransform * new Transform3D(Basis.FromEuler(new(0, -Mathf.Pi / 2, 0)), new(-.454f, .46f, -.03f));
        Window(art, Vector3.Zero, .19f, .24f, glass, trim);
        art.Transform = houseTransform;
        for (int i = 0; i < 3; i++) art.RoundedBox(new(.12f, .04f - i * .016f, .43f + i * .10f), new(.34f + i * .07f, .055f, .13f), .024f, new("bcb49a"));
        art.Transform = old;
    }

    private static void Window(Sculptor art, Vector3 p, float width, float height, Color glass, Color trim)
    {
        art.RoundedBox(p, new(width + .055f, height + .055f, .042f), .025f, trim);
        art.RoundedBox(p + new Vector3(0, 0, .025f), new(width, height, .018f), .018f, glass);
        art.RoundedBox(p + new Vector3(0, 0, .039f), new(.017f, height, .021f), .006f, trim);
        art.RoundedBox(p + new Vector3(0, -.01f, .039f), new(width, .015f, .021f), .005f, trim);
        art.RoundedBox(p + new Vector3(0, -height * .58f, .028f), new(width + .08f, .035f, .09f), .012f, trim);
    }

    private static void Arch(Sculptor art, Vector3 p, float width, float height, float depth, Color fill, Color trim)
    {
        float radius = width / 2, spring = height - radius;
        art.RoundedBox(p + new Vector3(0, spring / 2, 0), new(width, spring, depth), .008f, fill);
        for (int i = 0; i < 12; i++)
        {
            float a = i * Mathf.Pi / 12, b = (i + 1) * Mathf.Pi / 12;
            var v1 = p + new Vector3(Mathf.Cos(a) * radius, spring + Mathf.Sin(a) * radius, depth * .5f);
            var v2 = p + new Vector3(Mathf.Cos(b) * radius, spring + Mathf.Sin(b) * radius, depth * .5f);
            art.Face(p + new Vector3(0, spring, depth * .5f), v1, v2, fill);
            art.Tube(v1, v2, .023f, .023f, trim, 6);
        }
        art.Tube(p + new Vector3(-radius, 0, .012f), p + new Vector3(-radius, spring, .012f), .024f, .024f, trim, 6);
        art.Tube(p + new Vector3(radius, 0, .012f), p + new Vector3(radius, spring, .012f), .024f, .024f, trim, 6);
        for (int i = -1; i <= 1; i++) art.RoundedBox(p + new Vector3(i * width * .24f, spring * .47f, depth * .56f), new(.006f, spring * .87f, .006f), .002f, fill.Darkened(.23f));
    }

    private static void Dock(Sculptor art, float r)
    {
        Color timber = new("977145"), cut = new("b19466");
        float x = r * .56f;
        for (int i = 0; i < 11; i++)
            art.RoundedBox(new(x, .145f, r * (.40f + i * .095f)), new(r * .46f, .09f, r * .09f), .018f, timber.Lightened(i % 3 * .03f));
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(x + side * r * .15f, .072f, r * .88f), new(r * .055f, .10f, r * 1.09f), .01f, timber.Darkened(.12f));
            for (int i = 0; i < 3; i++)
            {
                var bottom = new Vector3(x + side * r * .25f, -.08f, r * (.48f + i * .43f));
                art.Tube(bottom, bottom + new Vector3(0, .47f, 0), r * .049f, r * .042f, timber.Darkened(.09f), 9);
                art.Tube(bottom + new Vector3(0, .455f, 0), bottom + new Vector3(0, .485f, 0), r * .047f, r * .047f, cut, 9);
            }
        }
    }

    private static void Barrel(Sculptor art, Vector3 at, float size)
    {
        art.Ellipsoid(at + new Vector3(0, size * .65f, 0), new(size * .58f, size * .78f, size * .58f), new("977044"), 12, 7);
        for (int i = 0; i < 2; i++) art.Tube(at + new Vector3(0, size * (.27f + i * .78f), 0), at + new Vector3(0, size * (.37f + i * .78f), 0), size * .56f, size * .56f, new("514f42"), 12);
        art.Tube(at + new Vector3(0, size * 1.36f, 0), at + new Vector3(0, size * 1.41f, 0), size * .45f, size * .45f, new("b18b57"), 12);
    }

    private static void Palm(Sculptor art, Vector3 at, float height, uint seed)
    {
        float lean = .13f * height;
        for (int i = 0; i < 3; i++)
        {
            float t = i / 3f, t1 = (i + 1) / 3f;
            art.Tube(at + new Vector3(lean * t * t, height * t, 0), at + new Vector3(lean * t1 * t1, height * t1, 0), height * (.065f - t * .02f), height * (.065f - t1 * .02f), new Color("97774b").Lightened(i % 2 * .065f), 9);
        }
        Vector3 crown = at + new Vector3(lean, height, 0);
        for (int i = 0; i < 6; i++)
        {
            float a = i * Mathf.Tau / 6 + seed % 23;
            Frond(art, crown, a, height * (.62f + .065f * Mathf.Sin(i * 4.7f)), height * .15f, height * .18f, Leaf.Lightened((i % 3) * .035f));
        }
        for (int i = 0; i < 3; i++) art.Ellipsoid(crown + new Vector3((i - 1) * .045f, -.04f, .03f), Vector3.One * height * .045f, new("6d593b"), 8, 5);
    }

    private static void Shrub(Sculptor art, Vector3 at, float size, uint seed)
    {
        art.Boulder(at+Vector3.Up*size*.35f,new(size*1.4f,size,size),Leaf,seed);
        art.Boulder(at+new Vector3(size*.4f,size*.2f,size*.15f),new(size,size*.7f,size),Leaf.Lightened(.1f),seed+7);
    }

    private static void Frond(Sculptor art, Vector3 at, float angle, float length, float width, float lift, Color color)
    {
        Vector3 forward=new(Mathf.Cos(angle),0,Mathf.Sin(angle)), side=new(-forward.Z,0,forward.X);
        var shoulder=at+forward*length*.44f+Vector3.Up*lift;
        var tip=at+forward*length-Vector3.Up*length*.18f;
        var left=shoulder-side*width; var right=shoulder+side*width;
        var ridge=shoulder+Vector3.Up*width*.22f;
        art.Face(at,ridge,left,color); art.Face(left,ridge,tip,color);
        art.Face(at,right,ridge,color.Lightened(.1f)); art.Face(ridge,right,tip,color.Lightened(.1f));
        art.Face(at,right,left,color.Darkened(.15f)); art.Face(left,right,tip,color.Darkened(.15f));
    }

    private sealed class Sculptor
    {
        private readonly Dictionary<string, SurfaceTool> surfaces = new();
        public Transform3D Transform = Transform3D.Identity;

        private SurfaceTool Surface(string key)
        {
            if (surfaces.TryGetValue(key, out var found)) return found;
            var surface = new SurfaceTool(); surface.Begin(Mesh.PrimitiveType.Triangles); surfaces.Add(key, surface); return surface;
        }
        public void Triangle(Vector3 a, Vector3 b, Vector3 c, Color ca, Color cb, Color cc, Vector3 na, Vector3 nb, Vector3 nc, string key = "matte")
        {
            Vector3 cross = (b - a).Cross(c - a);
            if (cross.LengthSquared() < 1e-14f) return;
            if (cross.Dot(na + nb + nc) < 0) { (b, c) = (c, b); (nb, nc) = (nc, nb); (cb, cc) = (cc, cb); }
            var s = Surface(key);
            void Vertex(Vector3 p, Color color, Vector3 normal) { s.SetColor(color); s.SetUV(new(p.X, p.Z)); s.SetNormal((Transform.Basis * normal).Normalized()); s.AddVertex(Transform * p); }
            // Godot front faces use clockwise winding. Our geometric normals are explicit.
            Vertex(a, ca, na); Vertex(c, cc, nc); Vertex(b, cb, nb);
        }
        public void Face(Vector3 a, Vector3 b, Vector3 c, Color color)
        {
            Vector3 cross = (b - a).Cross(c - a);
            if (cross.LengthSquared() < 1e-14f) return;
            Vector3 n = cross.Normalized();
            Triangle(a, b, c, color, color, color, n, n, n);
        }
        public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color color) { Face(a, b, c, color); Face(a, c, d, color); }
        public void Ellipsoid(Vector3 p, Vector3 radii, Color color, int sides = 12, int rings = 7)
        {
            Vector3 Unit(int i, int j) { float a = i * Mathf.Tau / sides, b = j * Mathf.Pi / rings; return new(Mathf.Sin(b) * Mathf.Cos(a), Mathf.Cos(b), Mathf.Sin(b) * Mathf.Sin(a)); }
            for (int j = 0; j < rings; j++) for (int i = 0; i < sides; i++)
            {
                var a = Unit(i, j); var b = Unit(i + 1, j); var c = Unit(i + 1, j + 1); var d = Unit(i, j + 1);
                Vector3 Normal(Vector3 q) => new Vector3(q.X / radii.X, q.Y / radii.Y, q.Z / radii.Z).Normalized();
                Triangle(p + a * radii, p + b * radii, p + c * radii, color, color, color, Normal(a), Normal(b), Normal(c));
                Triangle(p + a * radii, p + c * radii, p + d * radii, color, color, color, Normal(a), Normal(c), Normal(d));
            }
        }
        public void RoundedBox(Vector3 p, Vector3 size, float bevel, Color color)
        {
            Vector3 half = size * .5f, inner = half - Vector3.One * Mathf.Min(bevel, Mathf.Min(half.X, Mathf.Min(half.Y, half.Z)) * .95f);
            float radius = half.X - inner.X;
            // Four divisions put flat broad faces between rounded corners, unlike a low-poly sphere.
            float[] cuts = [-1, -.82f, .82f, 1];
            for (int axis = 0; axis < 3; axis++) for (int sign = -1; sign <= 1; sign += 2)
            {
                int u = (axis + 1) % 3, v = (axis + 2) % 3;
                (Vector3 P, Vector3 N) Point(int i, int j)
                {
                    Vector3 raw = Vector3.Zero; raw[axis] = half[axis] * sign; raw[u] = half[u] * cuts[i]; raw[v] = half[v] * cuts[j];
                    Vector3 clamped = raw.Clamp(-inner, inner), normal = (raw - clamped).Normalized();
                    return (p + clamped + normal * radius, normal);
                }
                for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++)
                {
                    var a = Point(i, j); var b = Point(i + 1, j); var c = Point(i + 1, j + 1); var d = Point(i, j + 1);
                    if (sign < 0) (b, d) = (d, b);
                    Triangle(a.P, b.P, c.P, color, color, color, a.N, b.N, c.N);
                    Triangle(a.P, c.P, d.P, color, color, color, a.N, c.N, d.N);
                }
            }
        }
        public void Boulder(Vector3 p, Vector3 size, Color color, uint seed)
        {
            var rng=new SeedRandom(seed); const int sides=6;
            var rings=new Vector3[3][];
            float[] heights=[-.48f,.08f,.49f]; float[] widths=[.52f,.44f,.31f];
            float phase=rng.Range(0,1);
            var offsets=Enumerable.Range(0,sides).Select(_=>rng.Range(.88f,1.12f)).ToArray();
            var angles=Enumerable.Range(0,sides).Select(i=>phase+i*Mathf.Tau/sides+rng.Range(-.13f,.13f)).ToArray();
            var shoulders=Enumerable.Range(0,sides).Select(_=>rng.Range(-.15f,.22f)).ToArray();
            var caps=Enumerable.Range(0,sides).Select(_=>rng.Range(.82f,1.15f)).ToArray();
            for(int j=0;j<3;j++)
            {
                rings[j]=new Vector3[sides];
                for(int i=0;i<sides;i++)
                {
                    float a=angles[i], radius=widths[j]*offsets[i]*(j==2?caps[i]:1);
                    rings[j][i]=p+new Vector3(Mathf.Cos(a)*radius+j*.035f,heights[j]+(j==2?Mathf.Cos(a)*.08f:j==1?shoulders[i]:0),Mathf.Sin(a)*radius-j*.025f)*size;
                }
            }
            for(int j=0;j<2;j++) for(int i=0;i<sides;i++)
            {
                int n=(i+1)%sides;
                Quad(rings[j][n],rings[j][i],rings[j+1][i],rings[j+1][n],color.Lightened(i%3*.035f));
            }
            var center=rings[2].Aggregate(Vector3.Zero,(sum,v)=>sum+v)/sides;
            Color cap=color.G>color.R*1.1f&&color.G>color.B*1.1f?color.Lightened(.12f):color.Lerp(new Color("d9cfac"),.60f);
            for(int i=0;i<sides;i++) Face(center,rings[2][(i+1)%sides],rings[2][i],cap);
        }
        public void Tube(Vector3 a, Vector3 b, float ra, float rb, Color color, int sides = 10)
        {
            Vector3 axis = (b - a).Normalized(), u = axis.Cross(MathF.Abs(axis.Y) < .9f ? Vector3.Up : Vector3.Right).Normalized(), v = axis.Cross(u);
            for (int i = 0; i < sides; i++)
            {
                float t = i * Mathf.Tau / sides, q = (i + 1) * Mathf.Tau / sides;
                Vector3 n = u * Mathf.Cos(t) + v * Mathf.Sin(t), m = u * Mathf.Cos(q) + v * Mathf.Sin(q);
                Triangle(a + n * ra, a + m * ra, b + m * rb, color, color, color, n, m, m);
                Triangle(a + n * ra, b + m * rb, b + n * rb, color, color, color, n, m, n);
                Face(a, a + m * ra, a + n * ra, color); Face(b, b + n * rb, b + m * rb, color);
            }
        }
        public Node3D Finish(string name)
        {
            var root = new Node3D { Name = name };
            foreach (var (key, surface) in surfaces)
            {
                if (!Materials.TryGetValue(key, out var material))
                {
                    material = key == "shelf"
                        ? new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/EnvironmentShallows.gdshader") }
                        : DioramaSurface.Material;
                    Materials.Add(key, material);
                }
                surface.SetMaterial(material); surface.Index();
                root.AddChild(new MeshInstance3D { Name = key, Mesh = surface.Commit(), CastShadow = key == "shelf" ? GeometryInstance3D.ShadowCastingSetting.Off : GeometryInstance3D.ShadowCastingSetting.On });
                surface.Dispose();
            }
            return root;
        }
    }
}
