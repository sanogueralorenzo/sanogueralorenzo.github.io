using Godot;

namespace CozySora;

public partial class CozyPlayer
{
    private Node3D _cat = null!, _gull = null!, _catBody = null!, _catHead = null!;
    private Node3D _gullBody = null!, _gullHead = null!, _gullTail = null!;
    private readonly List<CatLeg> _catLegs = new();
    private readonly List<Node3D> _catTail = new(), _gullLegs = new();
    private readonly List<GullWing> _gullWings = new();
    private readonly CozySolidMaterials _palette = new();
    private sealed record CatLeg(Node3D Hip, Node3D Knee, bool Front, int Side);
    private sealed record GullWing(Node3D Shoulder, Node3D Elbow, int Side);

    private static Node3D Group(Node3D parent, Vector3 at = default)
    {
        var result = new Node3D { Position = at };
        parent.AddChild(result);
        return result;
    }

    private static MeshInstance3D Sphere(Node3D parent, Vector3 at, float radius, Material material, Vector3? scale = null) =>
        CozyPrimitives.Instance(parent, CozyPrimitives.SphereMesh(radius, radius * 2, 12, 8), at, material, scale ?? Vector3.One);

    private static MeshInstance3D Capsule(Node3D parent, Vector3 at, float radius, float length, Material material) =>
        CozyPrimitives.Instance(parent, new CapsuleMesh { Radius = radius, Height = length + radius * 2, RadialSegments = 10, Rings = 5 }, at, material);

    private static MeshInstance3D Cone(Node3D parent, Vector3 at, float radius, float height, Material material) =>
        CozyPrimitives.Instance(parent, CozyPrimitives.CylinderMesh(radius, 0, height, 6), at, material);

    private void BuildCat()
    {
        _cat = Group(this);
        _cat.Name = "TabbyCat";
        _cat.Scale = Vector3.One * 1.35f;
        _catBody = Group(_cat);
        var orange = _palette.Color("df8b3c");
        var cream = _palette.Color("f5e9d2");
        var stripe = _palette.Color("8a4a22");
        var green = _palette.Color("5ea34a");
        var black = _palette.Color("1a1410");
        var pink = _palette.Color("e9a3a0");
        Capsule(_catBody, new(0, .26f, 0), .105f, .27f, orange).Rotation = new(Mathf.Pi / 2, 0, 0);
        Capsule(_catBody, new(0, .215f, 0), .075f, .22f, cream).Rotation = new(Mathf.Pi / 2, 0, 0);
        Sphere(_catBody, new(0, .28f, .13f), .11f, orange);
        Sphere(_catBody, new(0, .25f, .2f), .1f, cream, new(1, .8f, .7f));
        _catHead = Group(_catBody, new(0, .36f, .26f));
        Sphere(_catHead, Vector3.Zero, .11f, orange, new(1.05f, .92f, .95f));
        Sphere(_catHead, new(0, -.03f, .075f), .052f, cream, new(1.25f, .8f, 1));
        Sphere(_catHead, new(0, -.012f, .125f), .012f, pink);
        foreach (int side in new[] { -1, 1 })
        {
            var ear = Cone(_catHead, new(side * .065f, .1f, -.01f), .04f, .08f, orange);
            ear.Rotation = new(-.2f, 0, -side * .35f);
            var inner = Cone(_catHead, new(side * .065f, .095f, 0), .02f, .05f, pink);
            inner.Rotation = ear.Rotation;
            Sphere(_catHead, new(side * .045f, .015f, .09f), .017f, green);
            Sphere(_catHead, new(side * .045f, .015f, .104f), .008f, black);
            CozyPrimitives.Box(_catHead, new(side * .06f, .05f, .03f), new(.02f, .006f, .05f), stripe).Rotation = new(0, side * .5f, 0);
        }
        for (int i = 0; i < 4; i++)
            CozyPrimitives.Box(_catBody, new(0, .362f, .1f - i * .07f), new(.11f, .006f, .014f), stripe).Rotation = new(0, 0, i % 2 != 0 ? .08f : -.08f);
        for (int i = 0; i < 4; i++)
        {
            float x = i % 2 == 0 ? -.06f : .06f;
            float z = i < 2 ? .13f : -.12f;
            var hip = Group(_catBody, new(x, .24f, z));
            Capsule(hip, new(0, -.07f, 0), .03f, .12f, orange);
            var knee = Group(hip, new(0, -.14f, 0));
            Capsule(knee, new(0, -.05f, 0), .024f, .09f, orange);
            Sphere(knee, new(0, -.1f, .012f), .03f, cream, new(1, .7f, 1.2f));
            _catLegs.Add(new(hip, knee, i < 2, i % 2));
        }
        var previous = _catBody;
        for (int i = 0; i < 7; i++)
        {
            var joint = Group(previous, i == 0 ? new(0, .3f, -.19f) : new(0, 0, -.06f));
            Capsule(joint, new(0, 0, -.03f), .028f - i * .002f, .05f, i % 2 != 0 ? stripe : orange).Rotation = new(Mathf.Pi / 2, 0, 0);
            _catTail.Add(joint);
            previous = joint;
        }
    }

    private void AnimateCat(float dt)
    {
        float running = Mathf.Min(1, _speed / 5.5f);
        if (_speed > .2f) _gaitPhase += dt * (6 + _speed * 2.2);
        float amplitude = .25f + running * .65f;
        foreach (var leg in _catLegs)
        {
            double phase = _gaitPhase + (leg.Front ? 0 : Math.PI * .9) + (leg.Side != 0 ? .35 : 0);
            leg.Hip.Rotation = new((float)Math.Sin(phase) * amplitude * (leg.Front ? 1 : 1.1f), 0, 0);
            leg.Knee.Rotation = new(Mathf.Max(0, -(float)Math.Cos(phase)) * amplitude * 1.2f * (leg.Front ? 1 : -.5f) + (leg.Front ? .1f : -.15f), 0, 0);
            if (!Grounded)
            {
                leg.Hip.Rotation = new(leg.Front ? -.9f : .8f, 0, 0);
                leg.Knee.Rotation = new(leg.Front ? .6f : -.6f, 0, 0);
            }
        }
        _catBody.Position = new(0, (float)(Math.Abs(Math.Sin(_gaitPhase)) * .035 * running + (_speed < .2f ? Math.Sin(_elapsed * 2.2) * .004 : 0)), 0);
        _catBody.Rotation = new((float)Math.Sin(_gaitPhase) * .07f * running, 0, 0);
        _catHead.Rotation = new((float)(-.15 - Math.Sin(_gaitPhase) * .06 * running + (_speed < .2f ? Math.Sin(_elapsed * 1.3) * .05 : 0)),
            _speed < .2f ? (float)Math.Sin(_elapsed * .7) * .35f : 0, 0);
        for (int i = 0; i < _catTail.Count; i++)
            _catTail[i].Rotation = new((float)(.35 - i * .02 + Math.Sin(_elapsed * 3 + i * .6) * .12 * (.5 + running) + (i == 0 ? .4 : 0)),
                (float)Math.Sin(_elapsed * 2.2 + i * .8) * .18f, 0);
    }

    private void BuildGull()
    {
        _gull = Group(this);
        _gull.Name = "Seagull";
        _gull.Scale = Vector3.One * 1.25f;
        _gullBody = Group(_gull);
        var white = _palette.Color("f6f3ea");
        var grey = _palette.Color("a9b1b8");
        var black = _palette.Color("2a2a2e");
        var yellow = _palette.Color("e8b64a");
        var red = _palette.Color("d0503a");
        var body = Capsule(_gullBody, Vector3.Zero, .085f, .24f, white);
        body.Rotation = new(Mathf.Pi / 2, 0, 0);
        body.Scale = new(1, .9f, 1);
        var back = Capsule(_gullBody, new(0, .035f, -.01f), .07f, .2f, grey);
        back.Rotation = new(Mathf.Pi / 2, 0, 0);
        back.Scale = new(1.05f, .7f, 1);
        _gullHead = Group(_gullBody, new(0, .055f, .2f));
        Sphere(_gullHead, Vector3.Zero, .068f, white, new(.95f, .95f, 1.1f));
        Cone(_gullHead, new(0, -.012f, .11f), .022f, .09f, yellow).Rotation = new(Mathf.Pi / 2, 0, 0);
        Sphere(_gullHead, new(0, -.022f, .12f), .008f, red);
        foreach (int side in new[] { -1, 1 }) Sphere(_gullHead, new(side * .045f, .02f, .045f), .011f, black);
        _gullTail = Group(_gullBody, new(0, 0, -.16f));
        CozyPrimitives.Box(_gullTail, new(0, 0, -.07f), new(.14f, .012f, .14f), white);
        CozyPrimitives.Box(_gullTail, new(0, 0, -.135f), new(.15f, .014f, .03f), black);
        foreach (int side in new[] { -1, 1 })
        {
            var shoulder = Group(_gullBody, new(side * .06f, .05f, .02f));
            CozyPrimitives.Box(shoulder, new(side * .17f, 0, -.02f), new(.34f, .012f, .19f), grey);
            CozyPrimitives.Box(shoulder, new(side * .17f, -.002f, -.14f), new(.34f, .01f, .06f), white);
            var elbow = Group(shoulder, new(side * .34f, 0, 0));
            CozyPrimitives.Box(elbow, new(side * .16f, 0, -.05f), new(.32f, .01f, .15f), grey);
            CozyPrimitives.Box(elbow, new(side * .29f, 0, -.07f), new(.1f, .011f, .12f), black);
            _gullWings.Add(new(shoulder, elbow, side));
            var leg = Group(_gullBody, new(side * .035f, -.05f, -.03f));
            Capsule(leg, new(0, -.05f, 0), .008f, .084f, yellow);
            CozyPrimitives.Box(leg, new(0, -.1f, .015f), new(.04f, .008f, .05f), yellow);
            _gullLegs.Add(leg);
        }
    }

    private void AnimateGull(float dt)
    {
        _gull.Rotation = new(-_birdPitch, Mathf.Pi - _heading, -_bank);
        _animatedFlap = Mathf.Lerp(_animatedFlap, Perched ? 0 : _flap, Mathf.Min(1, dt * 6));
        _animatedPerch = Mathf.Lerp(_animatedPerch, Perched ? 1 : 0, Mathf.Min(1, dt * 5));
        _flapPhase += dt * (5.5 + _animatedFlap * 6.5) * Math.Tau / 3;
        float wave = (float)Math.Sin(_flapPhase);
        float perch = _animatedPerch;
        foreach (var wing in _gullWings)
        {
            float angle = .12f + (float)Math.Sin(_elapsed * 1.7) * .03f + wave * .75f * _animatedFlap;
            wing.Shoulder.Rotation = new(0, wing.Side * .55f * perch, -wing.Side * (angle * (1 - perch) + 1.35f * perch));
            float lag = (float)Math.Sin(_flapPhase - .9);
            wing.Elbow.Rotation = new(0, -wing.Side * .5f * perch,
                -wing.Side * ((.05f + Mathf.Max(0, -lag) * .55f * _animatedFlap + lag * .15f * _animatedFlap) * (1 - perch) + .9f * perch));
        }
        _gullBody.Position = new(0, (wave * .012f * _animatedFlap + (float)Math.Sin(_elapsed * 1.3) * .006f) * (1 - perch), 0);
        _gullBody.Rotation = new((-.05f - wave * .04f * _animatedFlap) * (1 - perch) + .35f * perch, 0, 0);
        _gullHead.Rotation = new((.15f + wave * .05f * _animatedFlap) * (1 - perch) - .25f * perch + (perch > .5f ? (float)Math.Sin(_elapsed * .9) * .08f : 0),
            perch > .5f ? (float)Math.Sin(_elapsed * .6) * .5f : 0, 0);
        _gullTail.Rotation = new(.1f + (float)Math.Sin(_elapsed * 2.1) * .04f - .35f * perch, 0, 0);
        foreach (var leg in _gullLegs)
        {
            leg.Rotation = new(-1.3f * (1 - perch), 0, 0);
            leg.Position = new(leg.Position.X, -.05f - .02f * perch, leg.Position.Z);
        }
    }
}
