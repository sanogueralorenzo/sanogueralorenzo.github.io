using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class BluewaterArt
{
    static readonly Color Honey = new("d3975b"), Bone = new("ffdfa7"), Iron = new("514052"), Hull = new("974e37");
    static readonly Dictionary<string, ArrayMesh> cache = [];

    public static Node3D Prop(SeaCountry style, string kind)
    {
        string key = $"{style.Accent}-{kind}";
        if (!cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry();
            var dye = new Color(style.Accent);
            var shade = new Color(style.Shadow);
            switch (kind)
            {
                case "convoy":
                case "prize":
                    Boat(b, dye, kind == "prize");
                    break;
                case "refuge":
                case "port":
                    Barge(b, shade, Honey);
                    b.RoundBox(new(0,.36f,0),new(1.25f,.48f,.99f),.065f,dye);
                    b.Polygon([new(-.85f,.59f,-.57f),new(.85f,.59f,-.57f),new(.85f,.96f,0),new(-.85f,.96f,0)], Bone,Vector3.Up);
                    b.Polygon([new(-.85f,.96f,0),new(.85f,.96f,0),new(.85f,.59f,.57f),new(-.85f,.59f,.57f)],dye,Vector3.Up);
                    Signal(b,new(-.91f,.2f,-.28f),1.35f,dye);
                    break;
                case "chain":
                    Barge(b,shade,Honey);
                    for(int i=-1;i<=1;i+=2)
                    {
                        b.Tube([new(i*.51f,.26f,-.16f),new(i*.51f,.94f,-.16f)],.085f,Iron);
                        b.Sphere(new(i*.51f,.94f,-.16f),Vector3.One*.12f,Bone);
                    }
                    b.Tube([new(-.56f,.80f,-.16f),new(.57f,.80f,-.16f)],.14f,Honey);
                    for(int i=0;i<7;i++) b.Sphere(new(-.30f+i*.10f,.78f,-.16f),new(.058f,.18f,.18f),shade);
                    break;
                case "tracks":
                case "buoy":
                    b.Sphere(new(0,.09f,0),new(.37f,.21f,.37f),dye);
                    b.Ring(new(0,.16f,0),.33f,.043f,Bone);
                    Signal(b,Vector3.Zero,.87f,dye);
                    break;
                case "gate":
                    foreach(int k in new[]{-1,1})
                    {
                        var p = new Vector3(k*1.65f,0,0);
                        b.Sphere(p+Vector3.Up*.11f,new(.28f,.22f,.28f),dye);
                        Signal(b,p,1.1f,k==1?Bone:dye);
                    }
                    break;
                case "wreck":
                    Barge(b,Hull,shade);
                    b.Tube([new(-.65f,.30f,.31f),new(-.41f,.74f,-.18f),new(.15f,1.0f,-.54f)],[.085f,.065f,.03f],Honey);
                    b.RoundBox(new(.29f,.32f,-.05f), new(.48f,.34f,.54f),.05f,dye);
                    break;
                default:
                    Barge(b,shade,dye);
                    Signal(b,new(0,.09f,0),1.45f,dye);
                    b.Ring(new(0,.30f,0),.34f,.07f,Honey);
                    break;
            }
            cache[key] = mesh = b.Mesh(DioramaSurface.Material);
        }
        var root = new Node3D();
        root.AddChild(new MeshInstance3D {Mesh=mesh});
        return root;
    }

    public static Node3D Commander(CampaignOrder order, SeaCountry style)
    {
        string key = "captain-" + order.Id;
        if (!cache.TryGetValue(key,out var mesh))
        {
            var b = new ActorGeometry();
            var dye = new Color(style.Accent); var shade = new Color(style.Shadow);
            Barge(b,shade,dye);
            b.Sphere(new(0,.55f,0),new(.89f,.51f,1.12f),dye);
            for(int i=-1;i<=1;i+=2)
            {
                for(int j=0;j<3;j++)
                {
                    float z=-.63f+j*.61f;
                    b.Tube([new(i*.69f,.40f,z),new(i*1.12f,.48f,z+.10f),new(i*1.37f,.02f,z+.29f)],[.14f,.18f,.035f],shade);
                }
                b.Sphere(new(i*.48f,.71f,-.86f),new(.16f,.14f,.14f),Bone);
                b.Sphere(new(i*.5f,.73f,-.95f),Vector3.One*.074f,Iron);
            }
            if (order.Duty is SeaDuty.Convoy or SeaDuty.Blockade)
            {
                for(int i=-1;i<=1;i+=2)
                {
                    b.Tube([new(i*.43f,.83f,.07f),new(i*.43f,1.39f,.19f)],[.21f,.17f],shade);
                    b.Ring(new(i*.43f,1.39f,.19f),.18f,.055f,Honey);
                    b.Sphere(new(i*.43f,1.39f,.19f),new(.13f,.04f,.13f),new("feaa65"));
                }
                b.Tube([new(0,.47f,-.60f),new(0,.60f,-1.65f)],[.23f,.16f],Iron);
            }
            else if (order.Duty == SeaDuty.Hunt)
            {
                b.Tube([new(0,.8f,.75f),new(0,1.43f,.50f),new(0,.80f,-.35f)],[.15f,.12f,.045f],dye);
                for(int side=-1;side<=1;side+=2)
                    b.Tube([new(side*.62f,.47f,-.69f),new(side*.77f,.57f,-1.37f),new(side*.42f,.72f,-1.71f)],[.17f,.14f,.022f],Bone);
            }
            else if (order.Duty == SeaDuty.Sounding)
            {
                for(int j=0;j<4;j++)
                {
                    float x=(j-1.5f)*.29f;
                    b.Tube([new(x,.72f,.35f),new(x,1.27f+.13f*j,.30f)],.092f,Honey);
                    b.Sphere(new(x,1.27f+.13f*j,.30f),Vector3.One*.13f,dye);
                }
            }
            else
            {
                b.Tube([new(-.65f,.60f,.45f),new(-.55f,1.37f,.17f),new(.59f,1.42f,-.35f)], [.14f,.12f,.09f],Honey);
                b.Tube([new(.59f,1.42f,-.35f),new(.59f,.71f,-.35f)],.034f,Bone);
                b.RoundBox(new(.59f,.62f,-.35f),new(.46f,.37f,.39f),.05f,shade);
            }
            b.Scale(Vector3.One*1.30f);
            cache[key] = mesh = b.Mesh(DioramaSurface.Material);
        }
        var root=new Node3D();
        root.AddChild(new MeshInstance3D {Mesh=mesh});
        root.AddChild(KeelwidowArt.Foam(1.5f,1.67f));
        return root;
    }

    static void Boat(ActorGeometry b, Color dye, bool cargo)
    {
        Vector3[] Rim(float width,float length,float height) =>
        [new(0,height+.12f,-length),new(width*.87f,height,-length*.55f),new(width,height,length*.37f),
            new(width*.64f,height+.04f,length*.87f),new(-width*.64f,height+.04f,length*.87f),
            new(-width,height,length*.37f),new(-width*.87f,height,-length*.55f)];
        b.Loft([Rim(.17f,.81f,-.05f),Rim(.53f,1,.22f),Rim(.55f,1.02f,.27f)],[Hull,dye]);
        b.Polygon(Rim(.52f,.99f,.23f),Honey,Vector3.Up);
        if(cargo) b.RoundBox(new(0,.46f,0),new(.72f,.49f,1.03f),.055f,Iron);
        else
        {
            for(int i=0;i<3;i++)
            {
                var p = new Vector3(0,.27f,-.56f+i*.44f);
                b.Ring(p,.225f,.046f,dye); b.Sphere(p+Vector3.Up*.015f,new(.175f,.055f,.17f),Hull);
            }
            Signal(b,new(.27f,.19f,.35f),.68f,Bone);
        }
    }
    static void Barge(ActorGeometry b,Color baseTint,Color edge)
    {
        b.RoundBox(new(0,.02f,0),new(1.67f,.28f,1.25f),.12f,baseTint);
        b.RoundBox(new(0,.21f,0),new(1.79f,.13f,1.35f),.08f,edge);
    }
    static void Signal(ActorGeometry b,Vector3 p,float height,Color dye)
    {
        b.Tube([p,p+Vector3.Up*height],.042f,Honey);
        var top = p+Vector3.Up*height;
        b.Polygon([top,top+new Vector3(.49f,-.07f,0),top+new Vector3(.33f,-.17f,0),top+new Vector3(.47f,-.27f,0),top+Vector3.Down*.23f],dye,Vector3.Back);
        b.Sphere(top,Vector3.One*.06f,Bone);
    }
}
