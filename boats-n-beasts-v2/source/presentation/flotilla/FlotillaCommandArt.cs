using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal static class FlotillaCommandArt
{
    static readonly Dictionary<string, ArrayMesh> cache = [];
    static readonly Color Oak = new("b17d57"), Honey = new("e9bd79"), Ink = new("463c55"), Bone = new("f6dfaa");
    internal static readonly Color[] Standards = [new("ffad82"), new("86d9cb"), new("e6b9f7")];
    internal static Node3D Hull(FleetRole role, SeaCountry country)
    {
        return Mesh($"{role}-{country.Accent}", b =>
        {
            var dye = Standards[(int)role];
            float width = role == FleetRole.Tug ? .83f : role == FleetRole.Tender ? .43f : .57f;
            float length = role == FleetRole.Tender ? 1.58f : role == FleetRole.Tug ? 1.19f : 1.50f;
            Shell(b, width, length, dye);
            if (role == FleetRole.Tender)
            {
                b.RoundBox(new(0, .43f, .08f), new(.61f, .16f, 1.28f), .10f, new("e9a374"));
                for (int i = -1; i <= 1; i++)
                {
                    b.Tube([new(-.60f, .46f, .44f + i * .39f), new(.59f, .46f, .44f + i * .39f)], .046f, Honey);
                    b.Tube([new(-.67f, .21f, .6f + i * .40f), new(-.35f, .48f, .23f + i * .40f)], .032f, Oak);
                    b.Tube([new(.67f, .21f, .6f + i * .40f), new(.35f, .48f, .23f + i * .40f)], .032f, Oak);
                }
                b.RoundBox(new(0, .51f, -.59f), new(.62f, .20f, .47f), .08f, Bone);
                b.RoundBox(new(0, .621f, -.59f), new(.44f, .026f, .13f), .02f, dye);
                b.Tube([new(-.27f, .49f, .82f), new(-.27f, 1.49f, .82f)], .038f, Ink);
                Flag(b, new(-.27f, 1.48f, .82f), dye, .49f);
            }
            else if (role == FleetRole.Tug)
            {
                foreach (int side in new[] { -1, 1 })
                {
                    b.RoundBox(new(side * .79f, .32f, .03f), new(.24f, .49f, 1.48f), .10f, Ink);
                    for (int i = -2; i <= 2; i++) b.RoundBox(new(side * .82f, .56f, i * .29f), new(.28f, .08f, .10f), .02f, Honey);
                }
                b.RoundBox(new(0, .54f, .17f), new(.90f, .53f, .71f), .09f, dye);
                b.RoundBox(new(0, .84f, .15f), new(1.1f, .12f, .87f), .06f, Ink);
                b.RoundBox(new(0, .69f, -.20f), new(.59f, .14f, .06f), .02f, Bone);
                b.Tube([new(0, .39f, -.61f), new(0, .81f, -.61f)], [.24f, .16f], Oak);
                b.Ring(new(0, .63f, -.61f), .20f, .04f, Honey);
                b.Tube([new(.42f, .44f, .65f), new(.42f, 1.52f, .65f)], .04f, Ink);
                Flag(b, new(.42f, 1.49f, .65f), dye, .53f);
            }
            else
            {
                b.Tube([new(0, .36f, -.06f), new(0, 2.14f, -.06f)], [.055f, .032f], Ink);
                b.Tube([new(-.77f, 1.59f, -.07f), new(.76f, 1.89f, -.07f)], .043f, Oak);
                b.Polygon([new(-.79f, 1.58f, -.05f), new(.72f, 1.88f, -.04f), new(.45f, .85f, .23f), new(-.55f, .71f, .22f)], dye, Vector3.Back);
                b.Polygon([new(0, 1.91f, -.1f), new(0, .57f, -.25f), new(0, .57f, -1.50f)], Bone, Vector3.Right);
                Flag(b, new(0, 2.15f, -.04f), dye, .67f);
                b.RoundBox(new(0, .46f, .75f), new(.62f, .21f, .49f), .07f, Oak);
            }
            Sailor(b, new(.16f, .38f, .63f), new(country.Accent), .86f);
            Sailor(b, new(-.15f, .38f, -.39f), dye, .82f);
        });
    }
    internal static Node3D Antagonist(FleetCommand fleet)
    {
        return Mesh("admiral-" + fleet.Country.Accent, b =>
        {
            var dye = new Color(fleet.Country.Accent); var shade = new Color(fleet.Country.Shadow); var red = new Color("b95751");
            Shell(b, 1.11f, 2.21f, red);
            b.RoundBox(new(0, .64f, .80f), new(1.48f, .57f, 1.09f), .10f, shade);
            b.RoundBox(new(0, .98f, .78f), new(1.66f, .16f, 1.25f), .08f, GoldTrim(dye));
            for (int side = -1; side <= 1; side += 2)
            {
                for (int i = -1; i <= 1; i++)
                {
                    b.Tube([new(side * .70f, .55f, i * .50f - .31f), new(side * 1.30f, .59f, i * .50f - .31f)], [.12f, .095f], Ink);
                    b.Ring(new(side * .86f, .48f, i * .50f - .31f), .11f, .027f, Honey);
                }
                b.Tube([new(side * .52f, .37f, -1.37f), new(side * .24f, .44f, -2.38f)], [.13f, .025f], GoldTrim(dye));
            }
            b.Tube([new(0, .46f, -.13f), new(0, 2.48f, -.13f)], .075f, Ink);
            if (fleet.Signature is FleetStrike.Echo or FleetStrike.Nets or FleetStrike.Swarm)
            {
                for (int i = -1; i <= 1; i++) b.Tube([new(i * .38f, .66f, -.61f), new(i * .38f, 1.31f, -.61f)], [.19f, .29f], dye);
            }
            else
            {
                b.Tube([new(0, .54f, -.91f), new(0, 1.13f, -1.53f)], [.25f, .19f], shade);
                b.ClosedTube([new(-.52f, .85f, -.92f), new(0, 1.38f, -1.22f), new(.53f, .85f, -.92f)], .063f, Honey);
            }
            b.Tube([new(-.88f, 2.08f, -.12f), new(.90f, 2.08f, -.12f)], .06f, Honey);
            b.Polygon([new(-.90f, 2.06f, -.10f), new(.91f, 2.06f, -.10f), new(.72f, 1.24f, .19f), new(-.71f, 1.19f, .19f)], red, Vector3.Back);
            b.Polygon([new(-.19f, 1.97f, -.08f), new(.19f, 1.97f, -.08f), new(.16f, 1.28f, .21f), new(-.14f, 1.24f, .21f)], Bone, Vector3.Back);
            Flag(b, new(0, 2.47f, -.13f), dye, .73f); Sailor(b, new(0, 1.06f, .85f), red, 1.16f);
        });
    }
    internal static Node3D Boom(SeaCountry country, PilotBoom span)
    {
        float length = System.Numerics.Vector2.Distance(span.A, span.B) * NativeStage3D.Unit;
        return Mesh($"boom-{country.Accent}-{length:F2}", b =>
        {
            float r = span.Radius * NativeStage3D.Unit;
            for (int i = -1; i <= 1; i++)
                b.Tube([new(-length * .48f, .13f, i * r * .60f), new(length * .49f, .12f, i * r * .60f)], [r * .32f, r * .34f], i == 0 ? Oak : Ink);
            for (int i = -1; i <= 1; i++)
            {
                float x = i * length * .43f; b.RoundBox(new(x, .23f, 0), new(.13f, .21f, r * 1.70f), .04f, Honey);
                b.Tube([new(x, .29f, 0), new(x, .69f, 0)], .053f, Ink);
                Flag(b, new(x, .67f, 0), i == 0 ? new Color(country.Accent) : Honey, .31f);
            }
        });
    }
    internal static Node3D Patient(SeaCountry country, bool pram) => Mesh("crew-pram-" + pram + country.Accent, b =>
    {
        if (pram) Shell(b, .32f, .72f, new Color("819b8d"));
        else
        {
            for (int i = -1; i <= 1; i++) b.Tube([new(i * .15f, .02f, -.37f), new(i * .15f, .04f, .39f)], .093f, Oak);
            b.Tube([new(-.26f, .11f, .15f), new(.26f, .12f, .15f)], .04f, Honey);
        }
        Sailor(b, new(0, pram ? .36f : .13f, 0), new Color(country.Accent), 1.35f);
        b.Tube([new(.10f, .4f, 0), new(.30f, .70f, .05f)], .042f, Bone);
    });
    internal static Node3D Hospital(SeaCountry country) => Mesh("fleet-hospital-" + country.Accent, b =>
    {
        Shell(b, .91f, 1.45f, new Color("648e85"));
        b.RoundBox(new(0, .52f, .22f), new(1.25f, .27f, 1.12f), .09f, Oak);
        foreach (float x in new[] { -.58f, .58f }) foreach (float z in new[] { -.27f, .78f })
            b.Tube([new(x, .48f, z), new(x, 1.14f, z)], .043f, Ink);
        b.Polygon([new(-.72f, 1.10f, -.35f), new(0, 1.40f, -.35f), new(0, 1.40f, .85f), new(-.72f, 1.10f, .85f)], Bone, Vector3.Up);
        b.Polygon([new(0, 1.40f, -.35f), new(.72f, 1.1f, -.35f), new(.72f, 1.1f, .85f), new(0, 1.40f, .85f)], new("81bab0"), Vector3.Up);
        b.Tube([new(0, .42f, -.91f), new(0, 1.89f, -.91f)], .046f, Ink);
        Flag(b, new(0, 1.87f, -.91f), new("82c8b9"), .67f);
        foreach (float x in new[] { -.47f, .47f }) b.RoundBox(new(x, .48f, -.74f), new(.38f, .22f, .36f), .045f, Bone);
        Sailor(b, new(.24f, .40f, -.65f), new Color(country.Accent), .90f);
    });
    internal static Node3D Haze(SeaCountry country) => Mesh("signal-haze-" + country.Accent, b =>
    {
        var color = new Color(country.Shadow).Lerp(new Color("b8cfbd"), .57f);
        for (int i = -2; i <= 2; i++)
        {
            float x = i * .50f, z = MathF.Sin(i * 1.75f) * .64f;
            b.Sphere(new(x, .17f, z), new(.76f, .27f, .55f), color.Lightened((i + 2) * .032f), 12, 7);
            b.Sphere(new(x + .13f, .35f, z + .18f), new(.47f, .31f, .37f), color.Lightened(.12f), 10, 6);
        }
    });
    static Color GoldTrim(Color dye) => dye.Lerp(Honey, .65f);
    static void Shell(ActorGeometry b, float w, float l, Color band)
    {
        Vector3[] edge(float width, float length, float y) => [new(0, y + .15f, -length), new(width * .76f, y, -length * .62f), new(width, y, length * .20f), new(width * .66f, y + .04f, length * .93f), new(-width * .66f, y + .04f, length * .93f), new(-width, y, length * .20f), new(-width * .76f, y, -length * .62f)];
        b.Loft([edge(w * .5f, l * .84f, -.14f), edge(w * .89f, l, .14f), edge(w, l, .31f), edge(w, l, .39f)], [Ink, Oak, band]);
        b.Polygon(edge(w * .96f, l * .97f, .39f), Oak, Vector3.Up); b.ClosedTube(edge(w, l, .41f), .037f, Honey);
    }
    static void Flag(ActorGeometry b, Vector3 at, Color dye, float length)
    {
        b.Polygon([at, at + new Vector3(length, .03f, 0), at + new Vector3(length * .70f, -.13f, .025f), at + new Vector3(length * .98f, -.23f, .04f), at + new Vector3(0, -.27f, .04f)], dye, Vector3.Back);
    }
    static void Sailor(ActorGeometry b, Vector3 p, Color coat, float scale)
    {
        b.Sphere(p + Vector3.Up * .15f * scale, new Vector3(.115f, .16f, .11f) * scale, coat);
        b.Sphere(p + Vector3.Up * .36f * scale, new Vector3(.105f, .11f, .10f) * scale, Bone);
        b.Sphere(p + Vector3.Up * .44f * scale, new Vector3(.13f, .05f, .14f) * scale, Ink);
    }
    static Node3D Mesh(string key, Action<ActorGeometry> carve)
    {
        if (!cache.TryGetValue(key, out var mesh))
        {
            var sculpture = new ActorGeometry(); carve(sculpture); mesh = sculpture.Mesh(DioramaSurface.Material); cache[key] = mesh;
        }
        return new MeshInstance3D { Mesh = mesh };
    }
}
