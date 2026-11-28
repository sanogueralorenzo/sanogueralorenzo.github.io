using Godot;
using System;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    // Crew shares the cached boat mesh, so every member follows its rocking deck.
    static void BoatCrew(ActorGeometry b)
    {
        Crewmate(b, new(-.114f, .34f, .407f), 0);
        Crewmate(b, new(.208f, .228f, -.125f), 1);
        Crewmate(b, new(-.208f, .229f, .073f), 2);
        var hub = new Vector3(-.077f, .477f, .305f);
        Vector3 Wheel(float angle, float radius) => hub + new Vector3(MathF.Cos(angle), MathF.Sin(angle), MathF.Cos(angle) * .19f) * radius;
        b.Tube([hub - Vector3.Up * .151f, hub], [.029f, .017f], DarkWood, 7);
        var rim = new Vector3[13];
        for (int i = 0; i < rim.Length; i++)
            rim[i] = Wheel(i * Mathf.Tau / (rim.Length - 1), .066f);
        b.Tube(rim, .009f, new("b87543"), 6);
        for (int i = 0; i < 6; i++)
        {
            float angle = i * Mathf.Tau / 6;
            b.Tube([hub, Wheel(angle, .082f)], .007f, DarkWood, 5);
            b.Tube([Wheel(angle, .072f), Wheel(angle, .085f)], .009f, Brass, 5);
        }
        b.Sphere(hub, new(.020f, .020f, .017f), Brass, 8, 4);
    }

    static void Crewmate(ActorGeometry b, Vector3 feet, int role,bool ashore=false)
    {
        Vector3 P(float x, float y, float z) => feet + new Vector3(x, y, z);
        Color navy = new("34436a"), cream = new("e8d8b2"), leather = new("65432e");
        Color skin = new(role == 0 ? "cc9969" : role == 1 ? "ac7146" : "e6b990");
        Color hair = new(role == 1 ? "302d2a" : "523729");
        Color coat = role == 0 ? navy : role == 1 ? new("a95638") : new("367c7d");
        // Different builds, not a uniform body with interchangeable hats.
        float hip = role == 1 ? .040f : role == 0 ? .035f : .030f, shoulder = role == 1 ? .061f : role == 0 ? .058f : .041f;
        float waist = role == 1 ? .092f : .106f, neck = role == 0 ? .218f : role == 1 ? .175f : .206f;
        float head = neck + .047f, headWidth = role == 1 ? .051f : role == 0 ? .052f : .041f;
        for (int side = -1; side <= 1; side += 2)
        {
            float spread = side * (role == 1 ? .034f : .023f);
            b.Tube(new[] { P(spread, .025f, 0), P(side * hip * .65f, waist, 0) },
                role == 1 ? .023f : .017f, role == 1 ? new("ddd0ad") : new("404659"), 6);
            b.RoundBox(P(spread, .022f, -.013f), new(role == 1 ? .049f : .040f, .043f, .067f), .008f, leather);
            if (role == 0)
                b.Tube(new[] { P(spread, .024f, 0), P(spread, .066f, 0) }, .021f, leather, 6);
        }
        Vector3[] BodyRing(float y, float width, float depth) =>
            [P(-width, y, -depth), P(width, y, -depth), P(width, y, depth), P(-width, y, depth)];
        var collar = BodyRing(neck - .01f, shoulder * .79f, .026f);
        b.Loft([BodyRing(waist, hip, .034f), BodyRing(neck - .043f, shoulder, .037f), collar], [coat, coat]);
        b.Polygon(collar, coat, Vector3.Up);
        b.RoundBox(P(0, (waist + neck) * .5f, -.037f), new(.040f, neck - waist - .014f, .008f), .003f,
            role == 1 ? skin : cream);
        Color sash = role == 0 ? Brass : role == 1 ? new("ba3930") : new("3eabb1");
        b.RoundBox(P(0, waist + .006f, 0), new(hip * 2 + .012f, .023f, .075f), .004f, sash);
        b.RoundBox(P(.013f, waist + .006f, -.042f), new(.019f, .018f, .009f), .002f, Brass);
        for (int side = -1; side <= 1; side += 2)
        {
            float reach = role == 1 ? .079f : .065f;
            var elbow = P(side * reach, neck - .075f, -.009f);
            var hand = role == 0 ? P(.036f + side * .061f, .137f, -.10f + side * .012f)
                : role == 2 && side < 0 ? P(-.066f, .160f, -.030f)
                : P(side * (role == 1 ? .057f : .046f), waist + .019f, -.038f);
            b.Tube(new[] { P(side * shoulder, neck - .035f, 0), elbow },
                new[] { role == 1 ? .030f : .023f, .019f }, role == 1 ? skin : coat, 6);
            b.Tube(new[] { elbow, hand }, role == 1 ? .021f : .014f, skin, 6);
            b.Sphere(hand, new(role == 1 ? .022f : .017f, .019f, .017f), skin, 8, 5);
            if (role == 0)
            {
                b.RoundBox(P(side * shoulder, neck - .032f, 0), new(.035f, .018f, .069f), .004f, Brass);
                b.Tube(new[] { hand + Vector3.Up * .006f, hand + Vector3.Up * .023f }, .020f, cream, 6);
            }
        }
        b.Tube(new[] { P(0, neck - .016f, 0), P(0, neck + .014f, 0) }, .018f, skin, 6);
        b.RoundBox(P(0, head, -.004f), new(headWidth * 2, .089f, .078f), .018f, skin);
        b.Sphere(P(0, head + .023f, .013f), new(headWidth + .004f, .039f, .044f), role == 2 ? cream : hair, 8, 5);
        b.Sphere(P(0, head - .005f, -.050f), new(.011f, .012f, role == 1 ? .021f : .011f), skin, 6, 4);
        for (int side = -1; side <= 1; side += 2)
        {
            b.Sphere(P(side * headWidth, head, -.002f), new(.010f, .014f, .009f), skin, 6, 4);
            b.RoundBox(P(side * .018f, head + .008f, -.044f), new(.009f, .010f, .006f), .002f, Pupil);
            b.Tube(new[] { P(side * .010f, head + .020f, -.044f), P(side * .027f, head + .023f, -.042f) }, .004f,
                role == 2 ? new("a99473") : hair, 5);
        }
        if (role == 0)
        {
            for (int side = -1; side <= 1; side += 2)
            {
                b.Polygon([P(side * .007f, waist, .037f), P(side * .044f, waist + .010f, .032f),
                    P(side * .049f, .050f, .046f), P(side * .013f, .039f, .049f)], navy, Vector3.Back);
                b.Tube(new[] { P(side * .024f, neck - .010f, -.032f), P(side * .014f, waist + .022f, -.044f) }, .005f, Brass, 5);
            }
            b.Sphere(P(0, head - .028f, -.016f), new(.045f, .033f, .039f), hair, 7, 4);
            b.Tube(new[] { P(-.030f, head - .009f, -.048f), P(0, head - .016f, -.052f), P(.030f, head - .009f, -.048f) }, .007f, hair, 5);
            Color hat = new("1b2f43"), gold = new("f7ca76");
            b.Sphere(P(0, head + .033f, .007f), new(.059f, .017f, .048f), Coral, 8, 5);
            b.Sphere(P(0, head + .066f, 0), new(.066f, .046f, .053f), hat, 8, 5);
            var brim = new[] { P(-.125f, head + .041f, .018f), P(-.071f, head + .068f, -.054f),
                P(0, head + .105f, -.083f), P(.071f, head + .068f, -.054f), P(.125f, head + .041f, .018f),
                P(.055f, head + .100f, .075f), P(0, head + .082f, .082f), P(-.055f, head + .100f, .075f) };
            b.Polygon(brim, hat, Vector3.Up); b.Polygon(brim, hat, Vector3.Down);
            b.ClosedTube(brim, .007f, gold, 5);
            b.Sphere(P(0, head + .068f, -.054f), new(.010f, .014f, .005f), cream, 6, 4);
        }
        else if (role == 1)
        {
            // A broad, bare-armed gunner: tied bandanna, brass goggles and a wide grin.
            b.RoundBox(P(0, head - .023f, -.044f), new(.039f, .012f, .007f), .002f, cream);
            b.Sphere(P(0, head - .040f, -.017f), new(.027f, .013f, .026f), hair, 6, 4);
            b.Sphere(P(0, head + .039f, 0), new(.058f, .030f, .049f), Coral, 8, 5);
            b.RoundBox(P(0, head + .025f, -.038f), new(.099f, .020f, .018f), .004f, Coral);
            for (int side = -1; side <= 1; side += 2)
            {
                b.Sphere(P(side * .027f, head + .040f, -.042f), new(.022f, .017f, .012f), Brass, 8, 4);
                b.Sphere(P(side * .027f, head + .041f, -.052f), new(.015f, .011f, .005f), Glass, 8, 4);
            }
            b.Sphere(P(.049f, head + .025f, .023f), new(.019f, .018f, .016f), Coral, 7, 4);
            b.Tube(new[] { P(.049f, head + .019f, .025f), P(.067f, head - .024f, .055f) }, new[] { .013f, .007f }, Coral, 5);
            b.Tube(new[] { P(.048f, head + .020f, .028f), P(.037f, head - .030f, .063f) }, new[] { .013f, .006f }, Coral, 5);
            b.Tube(new[] { P(-.037f, neck - .022f, -.038f), P(.034f, waist + .012f, -.044f) }, .010f, leather, 5);
            for (int i = 0; i < 3; i++)
                b.Tube(new[] { P(-.029f + i * .014f, .137f - i * .011f, -.047f),
                    P(-.019f + i * .014f, .151f - i * .011f, -.047f) }, .004f, Brass, 5);
        }
        else
        {
            // Slender stormcaller: one swept forelock, high ponytail and a split cape.
            b.Tube([P(-.042f,head+.015f,.024f),P(-.077f,head+.033f,.085f),P(-.11f,head+.007f,.13f)],[.026f,.023f,.008f],new("f7bf59"),6);
            b.Tube([P(-.054f,head+.034f,-.016f),P(0,head+.060f,-.031f),P(.052f,head+.033f,-.017f)],.023f,new("e9b455"),6);
            b.Tube(new[] { P(.026f, head + .059f, .009f), P(.044f, head + .096f, .033f), P(.027f, head + .088f, .061f) },
                new[] { .025f, .026f, .011f }, cream, 6);
            b.Tube(new[] { P(.033f, head + .042f, -.005f), P(.011f, head + .048f, -.040f), P(-.027f, head + .014f, -.046f) },
                new[] { .029f, .027f, .008f }, cream, 6);
            b.Tube(new[] { P(.020f, head + .063f, .018f), P(.044f, head + .066f, .028f) }, .006f, Brass, 5);
            Color purple = new("8152a3");
            b.Sphere(P(0, neck - .007f, 0), new(.056f, .025f, .049f), purple, 8, 4);
            var cape = new[] { P(-.045f, neck, .022f), P(.045f, neck, .022f), P(.058f, .064f, .061f),
                P(0, .082f, .060f), P(-.052f, .057f, .063f) };
            for (int i = 1; i < cape.Length - 1; i++)
            {
                Vector3[] panel = [cape[0], cape[i], cape[i + 1]];
                b.Polygon(panel, purple, Vector3.Back); b.Polygon(panel, coat, Vector3.Forward);
            }
            b.Sphere(P(-headWidth - .004f, head - .013f, -.005f), new(.007f, .012f, .005f), Brass, 6, 4);
            if(ashore)return;
            b.Tube(new[] { P(-.067f, .014f, -.034f), P(-.067f, .324f, -.034f) }, .008f, leather, 6);
            b.Tube(new[] { P(-.067f, .285f, -.034f), P(-.067f, .315f, -.034f) }, .013f, Brass, 6);
            b.Sphere(P(-.067f, .339f, -.034f), new(.025f, .028f, .025f), new("58dcc9"), 8, 5);
            b.Sphere(P(-.074f, .348f, -.053f), new(.008f, .009f, .005f), cream, 6, 4);
        }
    }
}
