using Godot;
using System;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    // Crew shares the cached boat mesh, so every member follows its rocking deck.
    static void BoatCrew(ActorGeometry b)
    {
        Crewmate(b, new(-.055f, .34f, .325f), 0);
        Crewmate(b, new(.157f, .222f, .115f), 1);
        Crewmate(b, new(-.162f, .222f, .145f), 2);
        // A small upright helm in front of the navigator.
        var hub = new Vector3(-.055f, .467f, .235f);
        b.Tube(new[] { hub - Vector3.Up * .13f, hub }, .012f, DarkWood, 6);
        var rim = new Vector3[9];
        for (int i = 0; i < rim.Length; i++)
        {
            float angle = i * Mathf.Tau / 8;
            rim[i] = hub + new Vector3(MathF.Cos(angle), MathF.Sin(angle), 0) * .050f;
        }
        b.Tube(rim, .006f, Wood, 6);
        for (int i = 0; i < 6; i++)
        {
            float angle = i * Mathf.Tau / 6;
            b.Tube(new[] { hub, hub + new Vector3(MathF.Cos(angle), MathF.Sin(angle), 0) * .064f }, .005f, Brass, 5);
        }
        b.Sphere(hub, new(.013f, .013f, .009f), Brass, 8, 4);
    }

    static void Crewmate(ActorGeometry b, Vector3 feet, int role)
    {
        Vector3 P(float x, float y, float z) => feet + new Vector3(x, y, z);
        Color navy = new("34436a"), skin = new(role == 1 ? "bb8051" : "d5a16e"), hair = new("49352b");
        Color coat = role == 0 ? navy : role == 1 ? new("795334") : new("70549a");
        Color shirt = new("e4d7b9"), boots = new("493c32");
        for (int side = -1; side <= 1; side += 2)
        {
            b.Tube(new[] { P(side * .023f, .025f, 0), P(side * .021f, .10f, 0) }, .018f, new("55555b"), 6);
            b.RoundBox(P(side * .025f, .022f, -.014f), new(.043f, .042f, .069f), .009f, boots);
        }
        b.RoundBox(P(0, .139f, 0), new(.102f, .107f, .069f), .016f, coat);
        b.RoundBox(P(0, .143f, -.036f), new(.041f, .086f, .006f), .002f, shirt);
        b.RoundBox(P(0, .099f, 0), new(.108f, .019f, .073f), .004f, DarkWood);
        b.RoundBox(P(0, .099f, -.039f), new(.020f, .017f, .008f), .002f, Brass);
        for (int side = -1; side <= 1; side += 2)
        {
            var elbow = P(side * .069f, .13f, -.013f);
            var hand = P(side * .047f, .124f, role == 0 ? -.074f : -.049f);
            b.Tube(new[] { P(side * .050f, .174f, 0), elbow }, new[] { .026f, .020f }, role == 1 ? shirt : coat, 6);
            b.Tube(new[] { elbow, hand }, .016f, skin, 6);
            b.Sphere(hand, new(.019f, .019f, .017f), skin, 8, 5);
        }
        b.Tube(new[] { P(0, .180f, 0), P(0, .204f, 0) }, .019f, skin, 6);
        b.RoundBox(P(0, .229f, -.004f), new(.091f, .094f, .078f), .021f, skin);
        b.Sphere(P(0, .248f, .010f), new(.051f, .044f, .045f), role == 2 ? shirt : hair, 8, 5);
        // Broad faces and a few tiny accents remain readable at the game's scale.
        b.Sphere(P(0, .226f, -.048f), new(.012f, .014f, .012f), skin, 6, 4);
        for (int side = -1; side <= 1; side += 2)
        {
            b.Sphere(P(side * .045f, .229f, -.002f), new(.010f, .015f, .010f), skin, 6, 4);
            b.RoundBox(P(side * .019f, .237f, -.044f), new(.008f, .011f, .006f), .002f, Pupil);
        }
        if (role == 0)
        {
            b.RoundBox(P(0, .202f, -.034f), new(.062f, .037f, .022f), .008f, hair);
            b.Sphere(P(0, .285f, 0), new(.052f, .044f, .047f), navy, 8, 5);
            // Three turned-up corners form a tricorn, with a narrow gold edge.
            var brim = new[] { P(-.086f, .273f, .022f), P(0, .318f, -.065f), P(.086f, .273f, .022f), P(0, .292f, .061f) };
            b.Polygon(brim, navy, Vector3.Up);
            b.Polygon(brim, navy, Vector3.Down);
            b.ClosedTube(brim, .005f, Brass, 5);
            b.Sphere(P(0, .291f, -.050f), new(.009f, .012f, .005f), Cream, 6, 4);
        }
        else if (role == 1)
        {
            b.RoundBox(P(0, .202f, -.035f), new(.063f, .041f, .024f), .007f, hair);
            b.Sphere(P(0, .268f, 0), new(.055f, .033f, .048f), Coral, 8, 5);
            b.RoundBox(P(0, .254f, -.038f), new(.091f, .019f, .017f), .004f, Coral);
            b.Sphere(P(.046f, .254f, .018f), new(.020f, .018f, .017f), Coral, 7, 4);
            b.Tube(new[] { P(.048f, .25f, .024f), P(.064f, .217f, .044f) }, new[] { .013f, .007f }, Coral, 5);
        }
        else
        {
            for (int i = 0; i < 4; i++)
                b.Sphere(P(-.033f + i * .022f, .268f + (i % 2) * .012f, -.011f), new(.025f, .026f, .039f), shirt, 6, 4);
            b.Sphere(P(0, .199f, 0), new(.061f, .025f, .049f), new("8560ae"), 8, 4);
            b.RoundBox(P(.035f, .157f, .039f), new(.035f, .095f, .016f), .004f, new("8560ae"));
        }
    }
}
