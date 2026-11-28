using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal static class TideHall
{
    public static MeshInstance3D Build(LandingRegion region)
    {
        var b = new ActorGeometry(); Color rock = new(region.Rock), cloth = new(region.Cloth), trim = new(region.Trim), wood = new("8b674e"), shade = new("665168"), light = new("eee0b7");
        bool round = region.Climate is IslandClimate.Calving or IslandClimate.Narrows or IslandClimate.Drumskin;
        float width = round ? .95f : 1.05f, ridge = round ? 1.56f : 1.84f;
        b.RoundBox(new(0, .10f, 0), new(width * 2.26f, .20f, 1.41f), .055f, rock);
        for (int side = -1; side <= 1; side += 2)
        {
            for (int bay = 0; bay < 3; bay++)
            {
                float z = -.57f + bay * .55f; b.Tube([new(side * width, .14f, z), new(side * (width - .045f), .99f, z)], .075f, wood, 7);
                b.Tube([new(side * width, .67f, z), new(side * (width - .27f), 1.08f, z)], [.059f, .041f], trim, 6);
                b.Tube([new(side * width, .13f, z), new(side * width, .31f, z)], .092f, rock, 7);
                if (bay == 2) { b.RoundBox(new(side * width, 1.05f, z), new(.22f, .14f, .17f), .024f, trim); b.Tube([new(side * width, .99f, z), new(side * width, .82f, z + .09f)], .018f, shade, 5); b.Crystal(new(side * width, .73f, z + .09f), new(.095f, .13f, .081f), light); }
            }
            for (int tile = 0; tile < 6; tile++)
            {
                float z = -.73f + tile * .242f; var a = new Vector3(0, ridge, z); var c = new Vector3(side * width * .69f, round ? ridge - .10f : ridge - .44f, z); var e = new Vector3(side * (width + .18f), 1.00f, z + .025f);
                Color tint = tile % 4 == 1 ? cloth.Lightened(.16f) : cloth;
                b.Polygon([a, c, c + Vector3.Back * .235f, a + Vector3.Back * .235f], tint, Vector3.Up);
                b.Polygon([c, e, e + Vector3.Back * .232f, c + Vector3.Back * .235f], tint.Darkened(.115f), Vector3.Up);
                if (tile % 2 == 1) b.Tube([a, c, e], [.016f, .024f, .019f], trim, 5);
                b.Polygon([e, e + Vector3.Back * .235f, e + Vector3.Back * .19f - Vector3.Up * .14f, e + Vector3.Back * .04f - Vector3.Up * .18f], tile % 3 == 0 ? light : tint, Vector3.Back);
            }
        }
        b.RoundBox(new(0, .62f, -.46f), new(width * 1.77f, .74f, .095f), .027f, shade);
        for (int n = 0; n < 4; n++)
        {
            float x = -width * .64f + n * .33f; b.RoundBox(new(x, .55f, -.395f), new(.22f, .39f, .035f), .016f, n % 2 == 0 ? cloth.Darkened(.16f) : wood);
        }
        b.Tube([new(0, ridge + .025f, -.78f), new(0, ridge + .025f, .83f)], .043f, trim, 7);
        if (region.Climate is IslandClimate.Waxwing or IslandClimate.Pitchwake or IslandClimate.Saltstep)
        {
            b.Tube([new(-width, 1.0f, .41f), new(-width, 1.91f, .41f)], .044f, wood, 6);
            b.Polygon([new(-width, 1.88f, .41f), new(-width + .54f, 1.76f, .45f), new(-width + .41f, 1.55f, .48f), new(-width, 1.60f, .41f)], trim, Vector3.Back);
        }
        return ShoreSculpture.Bake(b);
    }
}
