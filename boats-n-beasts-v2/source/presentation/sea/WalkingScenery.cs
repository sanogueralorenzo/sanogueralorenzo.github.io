using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class WalkingScenery
{
    public static void Draw(ActorGeometry b, SeaCountry country, bool port = false, bool bank = false)
    {
        var tint = new Color(country.Accent); var shadow = new Color(country.Shadow);
        Color wood = new("aa7650"), light = new("f5daac"), leaf = new("638c61");
        float length = bank ? 1.9f : 1.1f;
        void Bottle(Vector3 foot, float h)
        {
            b.Tube([foot, foot + Vector3.Up * (h * .53f), foot + Vector3.Up * (h * .68f), foot + Vector3.Up * h],
                [.13f, .15f, .069f, .064f], tint, 7);
            b.Ring(foot + Vector3.Up * h, .065f, .017f, light);
            b.Tube([foot + new Vector3(.07f, h * .15f, -.09f), foot + new Vector3(.08f, h * .45f, -.09f)], .013f, light);
        }
        switch (country.Climate)
        {
            case SeaClimate.Salt:
                for (int i = 0; i < 3; i++)
                {
                    float width = .96f - i * .23f;
                    b.RoundBox(new(i * .07f, .14f + i * .17f, 0), new(width, .22f, length - i * .21f), .085f, i % 2 == 0 ? light : tint);
                    b.RoundBox(new(i * .07f, .26f + i * .17f, 0), new(width * .73f, .028f, (length - i * .21f) * .79f), .038f, new("83b8a1"));
                }
                if (port)
                {
                    b.Tube([new(-.55f, .12f, .28f), new(-.55f, 1.08f, .28f)], .046f, wood);
                    b.Tube([new(-.82f, .83f, .28f), new(.27f, 1.12f, .28f)], .037f, wood);
                    b.Tube([new(.24f, 1.10f, .28f), new(.24f, .66f, .28f)], .016f, light);
                    b.Sphere(new(.24f, .59f, .28f), new(.13f, .10f, .12f), wood);
                }
                break;
            case SeaClimate.Bottle:
                for (int k = -1; k <= 1; k += 2)
                {
                    b.Tube([new(k * .33f, .01f, -length * .51f), new(k * .32f, .11f, length * .54f)], .07f, wood);
                    b.Tube([new(k * .32f, .06f, -.32f), new(k * .39f, .75f, .01f), new(k * .23f, 1.08f, .18f)], [.064f, .056f, .03f], wood);
                }
                b.Tube([new(-.46f, .87f, .04f), new(0, 1.0f, 0), new(.45f, .92f, .03f)], .052f, wood);
                for (int j = 0; j < (port ? 6 : 3); j++)
                {
                    float x = (j % 3 - 1) * .24f, z = (j / 3) * .36f - .15f;
                    Bottle(new(x, .13f, z), .48f + .16f * (j % 2));
                    b.Sphere(new(x, .95f, z), new(.23f, .07f, .15f), leaf);
                }
                break;
            case SeaClimate.Wax:
                b.Tube([new(0, .04f, -length * .52f), new(0, .19f, 0), new(.03f, .12f, length * .47f)], [.14f, .16f, .09f], wood);
                for (int k = -1; k <= 1; k += 2)
                {
                    float h = .77f + k * .14f;
                    b.Tube([new(0, .12f, k * .35f), new(k * .29f, h, k * .35f)], .043f, wood);
                    var wing = new Vector3(k * .37f, h, k * .35f);
                    b.Polygon([wing, wing + new Vector3(-k * .41f, .22f, -.14f), wing + new Vector3(-k * .61f, .18f, -.04f), wing + new Vector3(-k * .25f, -.04f, .11f)], tint, Vector3.Up);
                    b.Sphere(wing, new(.10f, .11f, .17f), shadow);
                    for (int j = 0; j < 3; j++)
                        b.Tube([wing + Vector3.Down * .15f, wing + new Vector3(k * j * .08f, -.25f - j * .09f, 0)], .024f, new("cc684c"));
                }
                if (port) b.RoundBox(new(0, .26f, 0), new(.70f, .43f, .67f), .055f, shadow);
                break;
            case SeaClimate.Sleep:
            case SeaClimate.Calving:
                bool calf = country.Climate == SeaClimate.Calving;
                b.Sphere(new(0, .08f, 0), new(.51f, calf ? .29f : .23f, length * .55f), shadow);
                b.Sphere(new(0, .22f, -.12f), new(.42f, .19f, length * .42f), tint);
                b.Sphere(new(0, .16f, -length * .54f), new(.29f, .16f, .27f), tint);
                for (int k = -1; k <= 1; k += 2)
                {
                    b.Tube([new(k * .32f, .14f, .01f), new(k * .62f, .035f, .22f), new(k * .67f, .03f, .36f)], [.13f, .09f, .026f], shadow);
                    b.Sphere(new(k * .17f, .22f, -length * .62f), new(.054f, .027f, .04f), light);
                }
                if (!calf)
                {
                    b.RoundBox(new(0, .48f, -.02f), new(.37f, .23f, .30f), .025f, wood);
                    b.Polygon([new(-.25f, .61f, -.22f), new(.25f, .61f, -.22f), new(.25f, .75f, 0), new(-.25f, .75f, 0)], light, Vector3.Up);
                    b.Polygon([new(-.25f, .75f, 0), new(.25f, .75f, 0), new(.25f, .61f, .20f), new(-.25f, .61f, .20f)], tint, Vector3.Up);
                }
                else
                {
                    b.Tube([new(.07f, .22f, 0), new(.06f, .79f, .04f)], .027f, wood);
                    b.Polygon([new(.06f, .76f, .04f), new(.32f, .51f, .06f), new(.06f, .50f, .04f)], light, Vector3.Back);
                }
                break;
            case SeaClimate.Tin:
                b.Sphere(new(0, .11f, 0), new(.47f, .18f, length * .48f), shadow);
                b.Tube([new(0, .19f, 0), new(0, .66f, .03f), new(0, .79f, .06f)], [.37f, .32f, .15f], tint, 9);
                b.Sphere(new(0, .47f, -.30f), new(.14f, .13f, .06f), new("415c6e"));
                b.Ring(new(0, .23f, 0), .37f, .039f, light);
                b.Tube([new(0, .75f, .04f), new(.18f, 1.03f, .12f), new(.37f, .89f, .21f)], [.041f, .033f, .025f], wood);
                if (port) b.Tube([new(-.51f, 0, .31f), new(-.51f, 1.18f, .31f), new(.36f, 1.08f, .21f)], .065f, wood);
                break;
            case SeaClimate.Drum:
                b.Tube([new(0, .02f, -.01f), new(0, .29f, 0), new(0, .43f, 0)], [.46f, .49f, .46f], shadow, 12);
                b.Sphere(new(0, .42f, 0), new(.47f, .047f, .46f), tint);
                for (int i = 0; i < 8; i++)
                {
                    float a = i * Mathf.Tau / 8;
                    b.Tube([new(MathF.Cos(a)*.46f,.06f,MathF.Sin(a)*.46f),
                        new(MathF.Cos(a+.26f)*.49f,.41f,MathF.Sin(a+.26f)*.49f)], .019f, light);
                }
                for (int k = -1; k <= 1; k += 2)
                    b.Tube([new(k * .18f, .47f, -.28f), new(k * .31f, .55f, length * .49f)], [.032f, .065f], wood);
                break;
            case SeaClimate.Pitch:
                b.RoundBox(new(0, .08f, 0), new(.82f, .19f, length), .06f, wood);
                b.Tube([new(0, .20f, .16f), new(0, .82f, .14f)], [.22f, .15f], shadow, 8);
                for (int i = 0; i < 5; i++)
                    b.Ring(new(0, .23f + i * .095f, .16f), .21f - i * .009f, .027f, tint);
                for (int k = -1; k <= 1; k += 2)
                    b.Tube([new(0, .19f, -.39f), new(k * .30f, .23f, -.47f), new(k * .39f, .45f, -.53f)], [.07f, .078f, .038f], shadow);
                if (port) b.Tube([new(-.45f, .13f, .29f), new(-.49f, 1.07f, .34f), new(.35f, 1.24f, -.03f)], [.08f, .06f, .045f], wood);
                break;
        }
    }
}
