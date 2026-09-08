using Godot;
using Further.Core;
using Further.Salvage;
namespace Further;

// Direct adaptation of CozySora's articulated cat construction and gait.
public partial class CharacterRig : Node3D
{
    MeshInstance3D glider=null!;
    static readonly SourceAnimation sourceAnimation=new();
    Node3D _cat=null!,_catBody=null!,_catHead=null!;
    readonly List<CatLeg> _catLegs=[];
    readonly List<Node3D> _catTail=[];
    readonly CozySolidMaterials _palette=new();
    sealed record CatLeg(Node3D Hip,Node3D Knee,bool Front,int Side);
    float _speed,attack;
    Role? role;
    public void Attack()=>attack=.22f;
    double _gaitPhase,_elapsed;
    bool Grounded=true;
    string fur="b8a591",stripeColor="64584e",coatColor="304b58";
    public void Build(Color coat,int variant=0,Role? role=null)
    {
        this.role=role;coatColor=coat.ToHtml(false);
        fur=(variant%3) switch{1=>"c28b57",2=>"899087",_=>"b8a591"};
        stripeColor=(variant%3) switch{1=>"79452a",2=>"38474a",_=>"64584e"};
        BuildCat();glider=Art.Source(this,"arms",new(0,1.45f,0),.65f);glider.MaterialOverride=Art.Material(new("c3b491"));glider.Visible=false;
    }
    public void Step(float dt,float speed,bool airborne=false,bool gliding=false)
    {
        _elapsed+=dt;_speed=speed;attack=MathF.Max(0,attack-dt);Grounded=!airborne;AnimateCat(dt);glider.Visible=gliding;glider.Scale=sourceAnimation.Wings((float)_elapsed)*.65f;
    }
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
        _cat.Scale = Vector3.One * 3.6f;
        _catBody = Group(_cat);
        var orange = _palette.Color(fur);
        var coat = _palette.Color(coatColor);
        var cream = _palette.Color("f5e9d2");
        var stripe = _palette.Color(stripeColor);
        var green = _palette.Color("5ea34a");
        var black = _palette.Color("1a1410");
        var pink = _palette.Color("e9a3a0");
        Capsule(_catBody, new(0, .26f, 0), .105f, .27f, coat).Rotation = new(Mathf.Pi / 2, 0, 0);
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
        var scarf = _palette.Color("963f34");
        var collar = Capsule(_catBody,new(0,.31f,.17f),.096f,.025f,scarf);
        collar.Rotation = new(Mathf.Pi/2,0,0);
        var knot = Sphere(_catBody,new(-.105f,.32f,.14f),.035f,scarf);
        var ribbon = Cone(_catBody,new(-.125f,.245f,.12f),.04f,.15f,scarf);
        ribbon.Rotation = new(0,0,-.25f);
        var buckle = _palette.Color("c6a267");
        Sphere(_catBody,new(0,.25f,.28f),.021f,buckle,new(1,1,.35f));
        if(role==null)
        {
            Sphere(_catHead,new(0,.105f,-.01f),.09f,_palette.Color("273d49"),new(1,.6f,1));
            using var brim=new SurfaceTool();brim.Begin(Mesh.PrimitiveType.Triangles);
            for(int i=0;i<36;i++)
            {
                Vector3 Rim(int j){float a=j*Mathf.Tau/36;return new(MathF.Sin(a)*.155f,.10f+MathF.Pow((1+MathF.Cos(a*3))*.5f,3)*.075f,MathF.Cos(a)*.15f);}
                foreach(var p in new[]{new Vector3(0,.11f,0),Rim(i),Rim(i+1)})brim.AddVertex(p);
            }
            brim.GenerateNormals();_catHead.AddChild(new MeshInstance3D{Mesh=brim.Commit(),MaterialOverride=Art.Material(new("273d49"))});
        }
        else
        {
            var gear=Group(_catBody,new(.075f,.36f,-.05f));
            var brass=_palette.Color("b49a65");var iron=_palette.Color("3d4d51");
            switch(role)
            {
                case Role.Gunner:
                    Capsule(gear,new(0,.055f,0),.035f,.22f,iron).Rotation=new(Mathf.Pi/2,0,0);
                    Sphere(gear,new(0,.055f,.15f),.04f,brass,new(1,1,.3f));break;
                case Role.Stormcaller:
                    Capsule(gear,new(0,.08f,0),.012f,.16f,brass);Sphere(gear,new(0,.19f,0),.05f,_palette.Color("8bc8bf"));break;
                case Role.Cook:
                    Sphere(gear,new(0,.045f,0),.075f,iron,new(1,.8f,1));Capsule(gear,new(.075f,.055f,0),.012f,.13f,brass).Rotation=new(0,0,Mathf.Pi/2);break;
                case Role.Duelist:
                    Capsule(gear,new(0,.04f,0),.024f,.29f,iron).Rotation=new(Mathf.Pi/2,0,.2f);Sphere(gear,new(0,.04f,.18f),.038f,brass);break;
                case Role.Harpooner:
                    Capsule(gear,new(0,.04f,0),.013f,.46f,brass).Rotation=new(Mathf.Pi/2,0,0);Cone(gear,new(0,.04f,.27f),.035f,.12f,iron).Rotation=new(Mathf.Pi/2,0,0);break;
                case Role.Tidekeeper:
                    Sphere(gear,new(0,.065f,0),.07f,_palette.Color("77a8a5"),new(1,1.2f,.7f));Capsule(gear,new(0,.16f,0),.024f,.04f,brass);break;
            }
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
        if(attack>0){_catBody.Rotation=new(-MathF.Sin(attack/.22f*Mathf.Pi)*.20f,0,0);_catLegs[0].Hip.Rotation=new(-.9f,0,0);}
        _catHead.Rotation = new((float)(-.15 - Math.Sin(_gaitPhase) * .06 * running + (_speed < .2f ? Math.Sin(_elapsed * 1.3) * .05 : 0)),
            _speed < .2f ? (float)Math.Sin(_elapsed * .7) * .35f : 0, 0);
        for (int i = 0; i < _catTail.Count; i++)
            _catTail[i].Rotation = new((float)(.35 - i * .02 + Math.Sin(_elapsed * 3 + i * .6) * .12 * (.5 + running) + (i == 0 ? .4 : 0)),
                (float)Math.Sin(_elapsed * 2.2 + i * .8) * .18f, 0);
    }

}
