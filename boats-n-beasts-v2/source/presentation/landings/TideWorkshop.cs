using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal static class TideWorkshop
{
    static readonly Color Wood = new("70554b"), Paper = new("e6ddbf"), Glass = new("94c9b3");
    public static MeshInstance3D Make(LandingRegion region, int variant)
    {
        var b = new ActorGeometry(); Color stone = new(region.Rock), trim = new(region.Trim), cloth = new(region.Cloth);
        switch (region.Climate)
        {
            case IslandClimate.Saltstep:
                b.Tube([new(0, .04f, 0), new(0, .30f, 0)], [.82f, .70f], stone, 10);
                b.Tube([new(0, .30f, 0), new(0, .34f, 0)], .63f, Glass, 10);
                for (int i = 0; i < 5; i++)
                {
                    float a = i * 1.62f; var p = new Vector3(MathF.Sin(a) * .48f, .29f, MathF.Cos(a) * .45f); var tip = p + new Vector3(.09f, .46f + .13f * (i % 3), 0);
                    b.Tube([p, tip], [.046f, .022f], cloth, 6); b.Sphere(tip + Vector3.Left * .13f, new(.22f, .085f, .1f), cloth.Lightened(.17f), 7, 4); b.Sphere(tip + new Vector3(.12f, .05f, 0), new(.16f, .12f, .08f), trim, 7, 4);
                }
                break;
            case IslandClimate.Bottlebrush:
                for (int i = 0; i < 5; i++)
                {
                    float a = i * 2.1f; var p = new Vector3(MathF.Cos(a) * .50f, 0, MathF.Sin(a) * .40f);
                    b.Tube([p, p + Vector3.Up * .21f, p + Vector3.Up * .54f, p + Vector3.Up * .74f, p + Vector3.Up * (.91f + .13f * (i % 3))], [.17f, .24f, .21f, .075f, .085f], i % 2 == 0 ? Glass : cloth, 8);
                    b.Ring(p + Vector3.Up * (.92f + .13f * (i % 3)), .081f, .020f, Paper);
                }
                break;
            case IslandClimate.Waxwing:
                b.Tube([new(0, .02f, 0), new(.04f, 1.62f, 0)], [.11f, .069f], Wood, 7);
                b.Tube([new(-1.02f, 1.28f, 0), new(1.07f, 1.50f, 0)], .048f, trim, 6);
                for (int i = 0; i < 8; i++)
                {
                    float x = -1 + i * .27f; var foot = new Vector3(x, 1.28f + (i * .028f), 0);
                    b.Polygon([foot, foot + new Vector3(.25f, .03f, 0), foot + new Vector3(.39f, -.55f + (i % 3) * .07f, .13f), foot + new Vector3(.15f, -.33f, .09f)], i % 3 == 0 ? Paper : cloth, Vector3.Back);
                }
                break;
            case IslandClimate.Narrows:
                foreach (int side in new[] { -1, 1 }) b.Tube([new(side * .82f, 0, 0), new(side * .89f, 1.08f, 0)], .095f, Wood, 7);
                for (int i = 0; i < 9; i++)
                {
                    float x = -.88f + i * .22f, z = .09f * MathF.Sin(i); var p = new Vector3(x, .56f + x * x * .57f, z);
                    float next = x + .22f; var q = new Vector3(next, .56f + next * next * .57f, z);
                    b.Polygon([p + new Vector3(0, 0, -.27f), q + new Vector3(0, 0, -.27f), q + new Vector3(0, -.07f, .31f), p + new Vector3(0, -.07f, .31f)], i % 3 == 0 ? Paper : cloth, Vector3.Up);
                }
                break;
            case IslandClimate.Tinmoon:
                b.RoundBox(new(0, .13f, 0), new(1.4f, .26f, .89f), .04f, stone);
                b.Tube([new(-.48f, .19f, 0), new(-.48f, 1.69f, 0), new(.67f, 1.69f, 0)], .085f, Wood, 7);
                b.Tube([new(.51f, 1.66f, 0), new(.51f, .64f, 0)], .020f, trim, 6); b.Crystal(new(.51f, .55f, 0), new(.18f, .26f, .16f), trim);
                b.Sphere(new(-.45f, 1.7f, 0), new(.28f, .28f, .28f), Paper, 10, 6);
                break;
            case IslandClimate.Drumskin:
                b.Tube([new(0, .10f, 0), new(0, .68f, 0)], [.64f, .75f], cloth, 12);
                b.Tube([new(0, .67f, 0), new(0, .71f, 0)], .74f, Paper, 12);
                for (int i = 0; i < 12; i++) { float a = i * Mathf.Tau / 12, c = (i + .5f) * Mathf.Tau / 12; b.Tube([new(.72f * MathF.Cos(a), .69f, .72f * MathF.Sin(a)), new(.63f * MathF.Cos(c), .12f, .63f * MathF.Sin(c))], .022f, trim, 5); }
                b.Tube([new(-.32f, .76f, .15f), new(.45f, .76f, -.19f)], .040f, Wood, 6); b.Sphere(new(-.35f, .76f, .17f), new(.10f, .08f, .10f), trim);
                break;
            case IslandClimate.Pitchwake:
                b.RoundBox(new(0, .15f, 0), new(1.47f, .30f, .99f), .047f, stone);
                foreach (float x in new[] { -.46f, .46f }) b.Tube([new(x, .25f, 0), new(x, .88f, 0)], .096f, Wood, 7);
                b.Tube([new(-.57f, .74f, 0), new(.60f, .74f, 0)], .27f, cloth, 10);
                for (int i = 0; i < 7; i++) { float x = -.36f + i * .12f; b.Tube([new(x, .74f, 0), new(x + .047f, .74f, 0)], .29f, trim.Darkened(.28f), 10); }
                b.Tube([new(.29f, .74f, .28f), new(.61f, .49f, .44f), new(.82f, .10f, .62f)], .038f, trim, 6); break;
            default:
                foreach (float x in new[] { -.61f, .61f }) b.Tube([new(x, .03f, 0), new(x, .77f, 0)], .072f, Wood, 7);
                b.Tube([new(-.66f, .76f, 0), new(0, .33f, 0), new(.66f, .76f, 0)], [.070f, .10f, .070f], trim, 8);
                b.Sphere(new(0, .53f, .03f), new(.36f, .32f, .27f), cloth, 10, 6); b.Sphere(new(.29f, .55f, .16f), new(.19f, .17f, .17f), Paper, 7, 4);
                for (int i = 0; i < 5; i++) { float a = i * Mathf.Tau / 5; b.Crystal(new(MathF.Cos(a) * .24f, .75f, MathF.Sin(a) * .17f), new(.079f, .13f, .064f), trim); }
                break;
        }
        var model = ShoreSculpture.Bake(b); model.RotationDegrees = new(0, (variant % 5 - 2) * 11, 0); return model;
    }
    public static void Crest(ActorGeometry b, LandingRegion region)
    {
        Color trim = new(region.Trim), cloth = new(region.Cloth);
        switch (region.Climate)
        {
            case IslandClimate.Saltstep:
            case IslandClimate.Bottlebrush:
            case IslandClimate.Calving:
                for (int i = 0; i < 5; i++) { float a = i * Mathf.Tau / 5; var p = new Vector3(.38f * MathF.Sin(a), 1.10f, .39f * MathF.Cos(a)); b.Tube([p, p + new Vector3(.12f, .39f, -.05f)], [.10f, .035f], cloth, 6); b.Sphere(p + new Vector3(.14f, .40f, -.05f), new(.12f, .13f, .085f), trim); }
                break;
            case IslandClimate.Waxwing:
            case IslandClimate.Narrows:
                foreach (float side in new[] { -1f, 1f }) for (int i = 0; i < 3; i++)
                { var p = new Vector3(side * .31f, 1.02f, .02f + i * .18f); b.Polygon([p, p + new Vector3(side * (.56f + i * .12f), .29f, .19f), p + new Vector3(side * .31f, -.09f, .23f)], i % 2 == 0 ? trim : cloth, Vector3.Up); }
                break;
            case IslandClimate.Drumskin:
                b.Tube([new(0, 1.04f, .17f), new(0, 1.26f, .17f)], [.41f, .39f], cloth, 12); b.Ring(new(0, 1.28f, .17f), .39f, .043f, trim); break;
            default:
                foreach (float x in new[] { -.35f, .35f }) { var p = new Vector3(x, 1.01f, 0); b.Tube([p, p + new Vector3(0, .47f, .08f), p + new Vector3(-x * .46f, .58f, .08f)], .06f, cloth, 7); b.Crystal(p + new Vector3(-x * .46f, .62f, .08f), new(.10f, .15f, .10f), trim); }
                break;
        }
    }
}
