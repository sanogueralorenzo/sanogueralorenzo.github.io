using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

public partial class Effects3D
{
    void DrawStormMark(LightningStrike strike)
    {
        var center = World(strike.Position, .092f);
        float radius = (LightningStrike.Radius + Voyage.BlastHullMargin) * NativeStage3D.Unit;
        float remaining = strike.Remaining / LightningStrike.Windup;
        var color = NauticalPalette.Lightning;
        foam.Arc(center, radius, 0, Mathf.Tau, .037f, Fade(color, .94f), 56);
        for (int i = 0; i < 8; i++)
        {
            float angle = i * Mathf.Tau / 8;
            foam.Arc(center, radius - .11f, angle + .10f, .42f, .026f, Fade(color, .50f), 7);
        }
        foam.Arc(center, Mathf.Lerp(.48f, radius - .21f, remaining), 0, Mathf.Tau,
            .027f, Fade(color, .74f), 40);

        var top = center + new Vector3(.20f, 0, -.38f);
        var elbow = center + new Vector3(-.14f, 0, .06f);
        var knee = center + new Vector3(.15f, 0, .01f);
        var bottom = center + new Vector3(-.19f, 0, .38f);
        foam.Ribbon(top, elbow, .045f, .065f, Fade(color, .90f));
        foam.Ribbon(elbow, knee, .065f, .065f, Fade(color, .90f));
        foam.Ribbon(knee, bottom, .065f, .023f, Fade(color, .90f));
    }

    void DrawStormBolt(Vector3 at, float age)
    {
        var color = NauticalPalette.Lightning;
        float glow = MathF.Exp(-age * 8);
        Span<Vector3> path =
        [
            at + new Vector3(-.86f, 5.8f, -.22f),
            at + new Vector3(.04f, 4.2f, .15f),
            at + new Vector3(-.44f, 3.55f, -.24f),
            at + new Vector3(.31f, 2.62f, .17f),
            at + new Vector3(-.23f, 1.63f, -.30f),
            at + new Vector3(.19f, .76f, .07f),
            at
        ];
        for (int i = 1; i < path.Length; i++)
        {
            foam.Ribbon(path[i - 1], path[i], .10f, .087f, Fade(color, glow * .91f));
            foam.Ribbon(path[i - 1], path[i], .044f, .041f, Fade(Colors.White, glow));
        }
        foam.Ribbon(path[2], path[2] + new Vector3(-.79f, -1.02f, -.38f), .060f, .019f, Fade(color, glow));
        foam.Ribbon(path[3], path[3] + new Vector3(.80f, -.88f, .53f), .053f, .014f, Fade(color, glow));

        float radius = (LightningStrike.Radius + Voyage.BlastHullMargin) * NativeStage3D.Unit;
        float edge = radius * Mathf.Lerp(.36f, 1.12f, Mathf.SmoothStep(0, 1, age));
        foam.Arc(at, edge, 0, Mathf.Tau, .045f + .025f * (1 - age), Fade(color, 1 - age), 56);
        foam.Arc(at, edge * .72f, 0, Mathf.Tau, .022f, Fade(Foam, (1 - age) * .65f), 40);
    }
}
