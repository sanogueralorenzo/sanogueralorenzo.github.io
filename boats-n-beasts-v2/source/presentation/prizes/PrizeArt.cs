using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class PrizeArt
{
    static readonly Color Oak = new("ab7653"), Gold = new("e6b776"), Dark = new("534457"), Cream = new("f6dcaa"), Ink = new("413765");
    static readonly Color[] flags = [new("ebbb69"), new("dd755d"), new("71c5a8"), new("b398ce")];
    static readonly Dictionary<string, ArrayMesh> meshes = [];
    public static Color Flag(int color) => flags[color];
    static Node3D Model(string id, Action<ActorGeometry> sculpt)
    {
        if (!meshes.TryGetValue(id, out var mesh)) { var b = new ActorGeometry(); sculpt(b); meshes[id] = mesh = b.Mesh(DioramaSurface.Material); }
        var root = new Node3D(); root.AddChild(new MeshInstance3D { Mesh = mesh }); return root;
    }
    public static Node3D Court(SeaCountry country)
    {
        var court = Model("court-" + country.Accent, b =>
        {
            var red = new Color("ac5451"); var crest = new Color(country.Accent);
            Vector3[] rail(float radius, float height) => Enumerable.Range(0, 8).Select(i =>
            {
                float a = i * Mathf.Tau / 8 + Mathf.Pi / 8;
                return new Vector3(MathF.Cos(a) * radius * 1.20f, height, MathF.Sin(a) * radius);
            }).ToArray();
            b.Loft([rail(1.11f, -.16f), rail(1.35f, .17f), rail(1.34f, .38f)], [Dark, red]);
            b.Polygon(rail(1.32f, .39f), Oak, Vector3.Up); b.ClosedTube(rail(1.34f, .38f), .057f, Gold);
            b.RoundBox(new(0, .48f, -.67f), new(1.87f, .17f, .74f), .08f, Dark);
            b.RoundBox(new(0, .73f, -.36f), new(1.18f, .44f, .39f), .065f, red);
            b.RoundBox(new(0, .96f, -.37f), new(1.29f, .084f, .52f), .045f, Gold);
            for (int j = -1; j <= 1; j++) b.RoundBox(new(-.15f + j * .19f, .995f, -.35f + j * .038f), new(.29f, .026f, .28f), .02f, Cream);
            b.Sphere(new(.37f, 1.017f, -.34f), new(.12f, .042f, .09f), red);
            b.Tube([new(.33f, 1.04f, -.46f), new(.46f, 1.32f, -.48f)], [.017f, .034f], Dark);
            foreach (int side in new[] { -1, 1 })
            {
                b.RoundBox(new(side * .90f, .51f, .10f), new(.23f, .21f, .76f), .05f, Dark);
                b.Tube([new(side * .85f, .38f, -.97f), new(side * .85f, 1.59f, -.97f)], .042f, Gold);
                b.Tube([new(side * 1.15f, .37f, .61f), new(side * 1.15f, 1.13f, .61f)], .055f, Dark);
                b.RoundBox(new(side * 1.15f, 1.20f, .61f), new(.21f, .30f, .21f), .045f, new("f8ce71"));
                b.RoundBox(new(side * 1.15f, 1.38f, .61f), new(.28f, .07f, .26f), .035f, Dark);
            }
            b.Tube([new(-.87f, 1.58f, -.97f), new(.87f, 1.58f, -.97f)], .038f, Gold);
            for (int i = -3; i <= 3; i++)
            {
                float x = i * .24f;
                b.Polygon([new(x - .12f, 1.55f, -.97f), new(x + .12f, 1.55f, -.97f), new(x + .12f, 1.29f, -.98f), new(x, 1.19f, -.98f), new(x - .12f, 1.29f, -.98f)], i % 2 == 0 ? red : Cream, Vector3.Back);
            }
            b.Tube([new(-1.18f, .35f, -.45f), new(-1.18f, 2.37f, -.45f)], [.061f, .034f], Dark);
            b.Polygon([new(-1.16f, 2.34f, -.44f), new(-.40f, 2.23f, -.41f), new(-.65f, 2.08f, -.40f), new(-.45f, 1.96f, -.39f), new(-1.16f, 2.02f, -.44f)], crest, Vector3.Back);
            b.Tube([new(-1.02f, 2.25f, -.41f), new(-1.02f, 2.07f, -.41f)], .034f, Gold);
            b.RoundBox(new(0, .38f, 1.18f), new(.63f, .12f, .59f), .04f, Oak);
        });
        void Seat(int role, float x, float y, float z, float scale, float turn)
        {
            var citizen = ActorArt3D.BoardingParty(role);
            citizen.Position = new(x, y, z); citizen.Scale = Vector3.One * scale; citizen.Rotation = new(0, turn, 0); court.AddChild(citizen);
        }
        Seat(2, .02f, .55f, -.74f, .93f, Mathf.Pi);
        Seat(1, -.86f, .57f, .17f, .71f, 1.36f);
        Seat(0, .83f, .57f, .13f, .72f, -1.28f);
        Seat(1, .48f, .39f, .75f, .65f, -.36f);
        return court;
    }
    public static Node3D Contact(PrizeContact contact)
    {
        return Model($"case-{contact.Color}-{contact.Rig}-{contact.Stamp}", b =>
        {
            var dye = flags[contact.Color];
            Vector3[] edge(float w, float l, float h) => [new(0,h+.16f,-l),new(w*.78f,h,-l*.61f),new(w,h,l*.28f),new(w*.70f,h+.06f,l*.90f),
                new(-w*.70f,h+.06f,l*.90f),new(-w,h,l*.28f),new(-w*.78f,h,-l*.61f)];
            b.Loft([edge(.27f, 1.29f, -.05f), edge(.70f, 1.41f, .25f), edge(.72f, 1.42f, .32f)], [Dark, dye]);
            b.Polygon(edge(.67f, 1.40f, .32f), Oak, Vector3.Up); b.ClosedTube(edge(.72f, 1.42f, .34f), .034f, Gold);
            int masts = contact.Rig == 1 ? 2 : 1;
            for (int i = 0; i < masts; i++)
            {
                float z = i * .71f - .15f, h = i == 0 ? 1.87f : 1.28f;
                b.Tube([new(0, .31f, z), new(0, h, z)], [.05f, .028f], Dark);
                float extent = contact.Rig == 2 ? .42f : .64f;
                b.Tube([new(-extent, h - .21f, z), new(extent, h - .21f, z)], .035f, Gold);
                if (contact.Rig == 3)
                {
                    b.Polygon([new(0, h - .17f, z), new(-.80f, .68f, z + .19f), new(0, .62f, z + .12f)], dye, Vector3.Back);
                    b.Polygon([new(0, h - .32f, z), new(.75f, .73f, z + .23f), new(0, .79f, z + .14f)], Cream, Vector3.Back);
                }
                else for (int side = -1; side <= 1; side += 2)
                {
                    float inner = contact.Rig == 0 ? .074f : 0;
                    b.Polygon([new(side * inner, h - .21f, z), new(side * extent, h - .21f, z), new(side * extent * .90f, .75f, z + .17f), new(side * inner, .70f, z + .19f)], i == 0 ? dye : Cream, Vector3.Back);
                }
                b.Polygon([new(0, h, z), new(.42f, h - .09f, z), new(.29f, h - .17f, z), new(0, h - .15f, z)], dye, Vector3.Back);
            }
            for (int i = 0; i <= contact.Stamp; i++) b.RoundBox(new(-.35f + i * .18f, .43f, .85f), new(.12f, .20f, .24f), .025f, Cream);
        });
    }
    public static Node3D Deck(PrizeBoarding room, SeaCountry country)
    {
        var floor = Model($"deck-{country.Accent}-{room.Work}", b =>
        {
            Vector3[] rim(float w, float z, float y) => [new(-w * .72f, y, -z), new(w * .72f, y, -z), new(w, y, -z * .69f), new(w, y, z * .72f), new(w * .76f, y, z), new(-w * .76f, y, z), new(-w, y, z * .72f), new(-w, y, -z * .69f)];
            b.Loft([rim(3.8f, 2.99f, -.19f), rim(4.45f, 3.39f, .24f), rim(4.44f, 3.39f, .41f)], [Dark, new(country.Accent)]);
            Vector3[] beak(float x, float half, float y) => [new(3.74f, y, -half), new(x, y + .16f, 0), new(3.74f, y, half)];
            b.Loft([beak(5.07f, .35f, -.52f), beak(5.91f, 1.76f, .25f), beak(5.98f, 1.77f, .42f)], [Dark, new(country.Accent)]);
            b.Polygon(beak(5.98f, 1.77f, .42f), Oak, Vector3.Up); b.ClosedTube(beak(5.98f, 1.77f, .45f), .060f, Gold);
            b.Tube([new(4.42f, .53f, 0), new(5.97f, .88f, 0), new(6.47f, 1.05f, 0)], [.13f, .08f, .043f], Oak);
            foreach (int side in new[] { -1, 1 })
            {
                b.Tube([new(4.10f, .53f, side * 1.35f), new(5.20f, .61f, side * .56f), new(6.38f, 1.02f, 0)], .024f, Gold);
                b.Tube([new(-3.26f, -.12f, side * 3.16f), new(-1.28f, -.20f, side * 3.16f), new(2.96f, -.10f, side * 3.16f)], .065f, Oak);
                for (int gun = -2; gun <= 2; gun++)
                {
                    float x = gun * 1.28f;
                    b.RoundBox(new(x, .21f, side * 3.24f), new(.44f, .35f, .27f), .035f, Dark);
                    b.Tube([new(x, .26f, side * 3.25f), new(x, .26f, side * 3.49f)], [.10f, .085f], Ink);
                }
            }
            b.RoundBox(new(-4.32f, .56f, 0), new(.35f, .39f, 3.21f), .13f, new(country.Shadow));
            for (int i = -2; i <= 2; i++) b.RoundBox(new(-4.51f, .57f, i * .58f), new(.055f, .20f, .32f), .022f, Cream);
            float mast = -.28f;
            b.Tube([new(mast, .40f, -3.13f), new(mast, 2.31f, -3.13f), new(mast, 3.41f, -3.13f)], [.14f, .10f, .055f], Oak);
            b.Tube([new(mast - 1.64f, 2.87f, -3.19f), new(mast + 1.68f, 2.87f, -3.14f)], .062f, Dark);
            Color sail = room.Work == DeckWork.Captain ? new Color(country.Accent) : Cream;
            for (int fold = -3; fold <= 3; fold++)
            {
                float x = mast + fold * .43f;
                b.Sphere(new(x, 2.75f, -3.12f), new(.31f, .15f, .18f), fold % 2 == 0 ? sail : sail.Darkened(.09f));
            }
            foreach (int side in new[] { -1, 1 })
                b.Tube([new(mast, 3.32f, -3.13f), new(mast + side * 2.0f, 1.6f, -3.07f), new(mast + side * 3.39f, .58f, -2.99f)], .030f, Dark);
            b.Polygon([new(mast, 3.43f, -3.13f), new(mast + 1.12f, 3.23f, -3.14f), new(mast + .78f, 3.09f, -3.12f), new(mast, 3.22f, -3.12f)], new(country.Accent), Vector3.Back);
            b.Polygon(rim(4.42f, 3.37f, .42f), Oak, Vector3.Up);
            b.ClosedTube(rim(4.43f, 3.38f, .51f), .071f, Gold);
            for (int j = -8; j <= 8; j++)
            {
                float x = j * .48f, z = Math.Abs(j) > 6 ? 2.85f : 3.30f;
                b.Tube([new(x, .429f, -z), new(x, .429f, z)], .012f, Dark, 4);
                for (int k = -1; k <= 1; k++)
                {
                    float seam = k * 1.73f + j % 3 * .34f;
                    b.Tube([new(x - .20f, .437f, seam), new(x + .20f, .437f, seam)], .012f, Dark, 4);
                }
            }
            foreach (int sign in new[] { -1, 1 })
            {
                for (int i = -2; i <= 2; i++) b.Tube([new(sign * 4.31f, .40f, i * 1.16f), new(sign * 4.31f, .95f, i * 1.16f)], .062f, Dark);
                b.Tube([new(sign * 4.31f, .88f, -2.4f), new(sign * 4.37f, .81f, 0), new(sign * 4.31f, .88f, 2.4f)], .047f, Gold);
            }
        });
        foreach (var spar in room.Spars)
        {
            var item = Prop(room.Work switch { DeckWork.Pump => "pump", DeckWork.Chains => "shackles", DeckWork.Magazine => "powder", DeckWork.Signal => "drum", DeckWork.Passenger => "awning", DeckWork.Captain => "wheel", _ => "crate" }, country.Accent);
            item.Scale = new(spar.Half.X * 1.9f, 1, spar.Half.Y * 1.65f); item.Position = OnDeck(spar.Center); floor.AddChild(item);
        }
        foreach (var at in new[] { room.Hatch, room.Ladder })
        {
            var exit = Prop(at == room.Hatch ? "hatch" : "ladder", country.Accent); exit.Position = OnDeck(at); floor.AddChild(exit);
        }
        var supply = Prop("crate", "b5ce9a"); supply.Position = OnDeck(room.Stash); supply.Scale = Vector3.One * .52f; floor.AddChild(supply);
        if (room.RequiresBrace) { var line = Prop("winch", country.Accent); line.Position = OnDeck(room.Hitch); floor.AddChild(line); }
        if (room.Work == DeckWork.Search)
        {
            for (int i = 0; i < 3; i++)
            {
                string kind = room.Method switch { ProofMethod.Balance => i < 2 ? "drum" : "crate", ProofMethod.Join => i == 1 ? "winch" : "hatch", ProofMethod.Sound => i < 2 ? "drum" : "hatch", _ => i == 1 ? "winch" : "crate" };
                var table = Prop(kind, country.Accent); table.Scale = Vector3.One * .57f; table.Position = OnDeck(room.BenchPoints[i]); floor.AddChild(table);
            }
        }
        if (room.Work == DeckWork.Search)
            foreach (var at in room.Lockers) { var lockbox = Prop("crate", country.Accent); lockbox.Position = OnDeck(at); lockbox.Scale = Vector3.One * .61f; floor.AddChild(lockbox); }
        return floor;
    }
    public static Vector3 OnDeck(System.Numerics.Vector2 p, float height = 0) => new(p.X, .48f + height, p.Y);
    public static Node3D Prop(string kind, string fabric) => Model(kind + fabric, b =>
    {
        var dye = new Color(fabric);
        switch (kind)
        {
            case "shackles":
                b.RoundBox(new(0, .15f, 0), new(.98f, .28f, .74f), .06f, Oak);
                for (int i = -2; i <= 2; i++) b.Ring(new(i * .18f, .3f, i % 2 * .12f), .18f, .046f, i % 2 == 0 ? Dark : Gold);
                break;
            case "powder":
                foreach (float x in new[] { -.23f, .23f })
                {
                    b.Tube([new(x, .05f, 0), new(x, .32f, 0), new(x, .64f, 0)], [.19f, .25f, .18f], Oak);
                    b.Ring(new(x, .24f, 0), .24f, .04f, Dark); b.Ring(new(x, .48f, 0), .22f, .04f, Dark);
                }
                break;
            case "drum":
                b.Tube([new(0, .03f, 0), new(0, .55f, 0)], [.38f, .38f], dye);
                for (int i = 0; i < 8; i++) { float a = i * Mathf.Tau / 8; b.Tube([new(MathF.Cos(a) * .39f, .06f, MathF.Sin(a) * .39f), new(MathF.Cos(a + .38f) * .39f, .53f, MathF.Sin(a + .38f) * .39f)], .021f, Gold); }
                b.Ring(new(0, .54f, 0), .38f, .048f, Cream); break;
            case "awning":
                b.RoundBox(new(0, .31f, 0), new(.89f, .16f, .74f), .08f, Oak);
                b.Tube([new(-.45f, 0, 0), new(-.45f, .97f, 0)], .055f, Dark);
                b.Tube([new(.45f, 0, 0), new(.45f, 1.12f, 0)], .055f, Dark);
                b.Polygon([new(-.48f, .99f, -.4f), new(.49f, 1.14f, -.4f), new(.49f, 1.14f, .4f), new(-.48f, .99f, .4f)], Cream, Vector3.Up); break;
            case "wheel":
                b.Tube([new(0, .01f, 0), new(0, .78f, 0)], [.14f, .09f], Oak);
                for (int i = 0; i < 8; i++) { float a = i * Mathf.Tau / 8; b.Tube([new(0, .67f, 0), new(MathF.Cos(a) * .43f, .67f + MathF.Sin(a) * .43f, 0)], .04f, Gold); }
                break;
            case "hatch":
                b.RoundBox(new(0, .016f, 0), new(1.11f, .12f, 1.06f), .045f, Dark);
                for (int j = -2; j <= 2; j++) b.Tube([new(j * .17f, .13f, -.44f), new(j * .17f, .13f, .43f)], .038f, Gold); break;
            case "ladder":
                for (int i = -1; i <= 1; i += 2) b.Tube([new(i * .31f, .06f, .47f), new(i * .31f, .58f, -.53f)], .069f, Oak);
                for (int i = 0; i < 5; i++) b.Tube([new(-.33f, .10f + i * .10f, .37f - i * .19f), new(.33f, .10f + i * .10f, .37f - i * .19f)], .041f, Gold); break;
            case "winch":
            case "pump":
                b.RoundBox(new(0, .08f, 0), new(.87f, .16f, .71f), .065f, Dark);
                b.Tube([new(0, .16f, 0), new(0, .70f, 0)], [.22f, .17f], Oak);
                for (int i = 0; i < 4; i++) b.Ring(new(0, .21f + i * .09f, 0), .21f, .032f, Gold);
                b.Tube([new(-.49f, .72f, 0), new(.49f, .72f, 0)], .053f, dye); break;
            default:
                b.RoundBox(new(0, .32f, 0), new(.96f, .64f, .87f), .065f, Oak);
                for (int i = -1; i <= 1; i += 2) b.RoundBox(new(i * .31f, .33f, 0), new(.10f, .68f, .91f), .018f, dye);
                b.Tube([new(-.41f, .67f, -.36f), new(.41f, .67f, .36f)], .032f, Gold); break;
        }
    });
}
