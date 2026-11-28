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
                    Boat(b, dye, kind == "prize",style.Climate);
                    break;
                case "picket":
                    Boat(b,dye,true,style.Climate);
                    for(int i=-1;i<=1;i+=2)
                    {
                        b.Tube([new(i*.30f,.54f,-.40f),new(i*.43f,.60f,-.89f)],[.12f,.085f],Iron);
                        b.RoundBox(new(i*.52f,.29f,.16f),new(.20f,.37f,.91f),.06f,shade);
                    }
                    Signal(b,new(0,.36f,.24f),1.03f,new("f67d59"));
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
            string name=order.Boss.ToLowerInvariant();
            bool creature(params string[] words)=>words.Any(word=>name.Contains(word,StringComparison.Ordinal));
            bool winged=creature("gull","kite","tern","bat","gannet","moth","hornet","petrel","wing","egret","swallow","heron","rook","bee","wren","jay","hawk");
            bool swimmer=creature("ray","skate","squid","fish","eel","shark","lamprey","fin","whale","turtle","porpoise","sturgeon","pike","carp");
            bool vessel=creature("hull","office","sledge","cutter","headwind","gate tender","bell","monitor","bailiff","clerk","oarsman","boat","lighter","wheel","standing order","port shear","barge","scow","engine","winch","spindle");
            if(order.Boss=="The Old Breakwater")
            {
                b.Sphere(new(0,.30f,.08f),new(1.02f,.39f,1.47f),shade);
                for(int k=0;k<6;k++)
                {
                    float z=-1.03f+k*.43f,h=.43f+.22f*MathF.Sin(k*.71f);
                    b.RoundBox(new(k%2==0?.10f:-.09f,h,z),new(1.57f,.43f,.51f),.115f,k%3==0?dye:Honey);
                    for(int j=-1;j<=1;j+=2)
                    {
                        b.Tube([new(j*.65f,.31f,z),new(j*1.05f,.30f,z+.06f),new(j*1.25f,.01f,z+.22f)],[.19f,.13f,.051f],shade);
                        if(k%2==0)b.Sphere(new(j*.48f,h+.24f,z),new(.14f,.12f,.17f),new("72976c"));
                    }
                }
                b.Sphere(new(0,.35f,-1.35f),new(.53f,.32f,.49f),shade);
                for(int k=-1;k<=1;k+=2)b.Sphere(new(k*.29f,.46f,-1.67f),new(.10f,.055f,.081f),Bone);
            }
            else if(order.Boss=="The Bottle Train")
            {
                for(int wagon=0;wagon<4;wagon++)
                {
                    float z=-1.18f+wagon*.72f,x=MathF.Sin(wagon*.99f)*.20f;
                    b.RoundBox(new(x,.18f,z),new(.88f,.25f,.73f),.09f,shade);
                    b.Tube([new(x,.29f,z),new(x,.66f,z),new(x,.83f,z),new(x,1.03f,z)],[.31f,.34f,.14f,.12f],dye,8);
                    b.Ring(new(x,1.02f,z),.139f,.032f,Bone);
                    for(int wheel=-1;wheel<=1;wheel+=2)b.Sphere(new(x+wheel*.46f,.17f,z),new(.16f,.18f,.20f),Honey);
                }
            }
            else if(order.Boss=="The Alarm Clock")
            {
                b.Sphere(new(0,.72f,.14f),new(.88f,.86f,.32f),dye);
                foreach(int face in new[]{-1,1})
                {
                    b.Sphere(new(0,.74f,.14f+face*.28f),new(.71f,.71f,.105f),Bone);
                    var pivot=new Vector3(0,.73f,.14f+face*.40f);
                    b.Tube([pivot+new Vector3(face*.35f,.39f,.01f),pivot,pivot+new Vector3(-face*.28f,-.12f,0)],[.043f,.072f,.057f],shade);
                    for(int numeral=0;numeral<8;numeral++)
                    {
                        float a=numeral*Mathf.Tau/8;
                        b.Sphere(pivot+new Vector3(MathF.Cos(a)*.53f,MathF.Sin(a)*.53f,-face*.021f),new(.037f,.050f,.023f),Honey);
                    }
                }
                for(int bell=-1;bell<=1;bell+=2)
                {
                    b.Sphere(new(bell*.53f,1.44f,.16f),new(.34f,.21f,.31f),Honey);
                    b.Tube([new(bell*.42f,.44f,.16f),new(bell*.71f,.06f,-.22f)],[.17f,.072f],shade);
                }
            }
            else if(winged)
            {
                b.Sphere(new(0,.63f,.07f),new(.45f,.54f,.89f),shade);
                b.Sphere(new(0,.95f,-.65f),new(.35f,.32f,.39f),dye);
                b.Tube([new(0,.95f,-.93f),new(0,.82f,-1.51f)],[.17f,.018f],Honey);
                for(int wing=-1;wing<=1;wing+=2)
                {
                    var shoulder=new Vector3(wing*.26f,.83f,-.25f);
                    var wrist=new Vector3(wing*1.11f,1.18f,-.67f);
                    b.Tube([shoulder,wrist,new(wing*1.90f,.85f,.04f)],[.15f,.12f,.035f],shade);
                    for(int j=0;j<4;j++)
                    {
                        float t=j*.23f;
                        var start=shoulder.Lerp(wrist,t);
                        var tip=new Vector3(wing*(1.23f+t),.56f+.21f*t,.92f-t);
                        b.Polygon([start,start.Lerp(wrist,.34f),tip,tip+new Vector3(-wing*.19f,.04f,.04f)],j%2==0?dye:Bone,Vector3.Up);
                    }
                    b.Sphere(new(wing*.27f,1.04f,-.81f),Vector3.One*.075f,Honey);
                }
            }
            else if(swimmer)
            {
                b.Sphere(new(0,.39f,-.06f),new(.63f,.34f,1.18f),dye);
                b.Tube([new(0,.34f,.62f),new(.17f,.53f,1.24f),new(.61f,.56f,1.68f),new(.47f,.85f,2.09f)],[.31f,.21f,.12f,.016f],shade);
                for(int fin=-1;fin<=1;fin+=2)
                {
                    b.Polygon([new(fin*.21f,.53f,-.74f),new(fin*1.53f,.38f,-.42f),new(fin*1.83f,.19f,.51f),new(fin*.43f,.39f,.63f)],shade,Vector3.Up);
                    b.Tube([new(fin*.41f,.53f,-.70f),new(fin*1.51f,.39f,-.4f),new(fin*1.79f,.21f,.40f)],[.068f,.045f,.013f],Honey);
                    b.Sphere(new(fin*.32f,.57f,-.87f),Vector3.One*.10f,Bone);
                }
            }
            else if(vessel)
            {
                Boat(b,dye,true,style.Climate);
                for(int side=-1;side<=1;side+=2)
                {
                    b.Tube([new(side*.53f,.32f,-.64f),new(side*.68f,.28f,.13f),new(side*.56f,.3f,.83f)],.12f,shade);
                    for(int j=0;j<3;j++)b.Tube([new(side*.46f,.47f,-.52f+.43f*j),new(side*.89f,.45f,-.49f+.43f*j)],.12f,Iron);
                }
                b.Tube([new(0,.27f,.25f),new(0,1.91f,.11f)],[.094f,.042f],Honey);
                b.Polygon([new(-.77f,1.77f,.12f),new(.77f,1.77f,.12f),new(.68f,.91f,-.15f),new(.18f,.81f,-.23f),new(-.69f,.93f,-.17f)],dye,Vector3.Back);
                b.Polygon([new(-.94f,1.18f,.05f),new(-.20f,1.29f,.06f),new(-.23f,.69f,-.21f),new(-.88f,.70f,-.10f)],Bone,Vector3.Back);
            }
            else
            {
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
            }
            if (order.Boss=="The Old Breakwater" || order.Boss=="The Bottle Train" || order.Boss=="The Alarm Clock")
                Signal(b,new(.45f,.62f,.31f),.62f,Honey);
            else if (order.Duty is SeaDuty.Convoy or SeaDuty.Blockade)
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

    static void Boat(ActorGeometry b, Color dye, bool cargo,SeaClimate climate)
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
                switch(climate)
                {
                    case SeaClimate.Salt:
                        b.RoundBox(p+Vector3.Up*.09f,new(.65f,.17f,.31f),.05f,Hull);
                        for(int sprout=-1;sprout<=1;sprout++)b.Sphere(p+new Vector3(sprout*.19f,.20f,0),new(.11f,.10f,.13f),new("789a68"));
                        break;
                    case SeaClimate.Bottle:
                        b.Tube([p,p+Vector3.Up*.22f,p+Vector3.Up*.31f,p+Vector3.Up*.42f],[.15f,.16f,.069f,.06f],dye,7);
                        b.Ring(p+Vector3.Up*.41f,.07f,.015f,Bone);
                        break;
                    case SeaClimate.Wax:
                        b.RoundBox(p+Vector3.Up*.10f,new(.54f,.20f,.35f),.06f,Honey);
                        for(int bar=-1;bar<=1;bar++)b.Tube([p+new Vector3(bar*.17f,.14f,-.14f),p+new Vector3(bar*.17f,.37f,0),p+new Vector3(bar*.17f,.14f,.14f)],.021f,dye);
                        b.Sphere(p+new Vector3(.08f,.19f,0),new(.07f,.07f,.09f),new("bf6552"));
                        break;
                    case SeaClimate.Tin:
                        b.Sphere(p+Vector3.Up*.10f,new(.21f,.25f,.17f),dye);
                        b.Sphere(p+new Vector3(.01f,.16f,-.14f),new(.066f,.071f,.02f),Iron);
                        break;
                    case SeaClimate.Drum:
                        b.Tube([p,p+Vector3.Up*.25f],[.21f,.20f],Hull,9);
                        b.Sphere(p+Vector3.Up*.26f,new(.21f,.034f,.21f),dye);
                        break;
                    case SeaClimate.Pitch:
                        for(int chain=-1;chain<=1;chain++)b.Ring(p+new Vector3(chain*.15f,.10f,0),.11f,.037f,Iron);
                        break;
                    case SeaClimate.Calving:
                        b.Sphere(p+Vector3.Up*.10f,new(.22f,.12f,.16f),dye);
                        b.Sphere(p+new Vector3(.17f,.13f,-.03f),new(.11f,.081f,.10f),dye);
                        b.Sphere(p+new Vector3(.23f,.16f,-.08f),new(.025f,.024f,.02f),Iron);
                        break;
                    case SeaClimate.Cinder:
                        b.Ring(p,.225f,.046f,dye); b.Sphere(p+Vector3.Up*.015f,new(.175f,.055f,.17f),Hull);
                        break;
                    case SeaClimate.Delta:
                        for(int n=-1;n<=1;n++)b.Tube([p+new Vector3(-.33f,.09f,n*.065f),p+new Vector3(.31f,.16f,n*.065f)],[.045f,.031f],new("9eaf72"));
                        break;
                    case SeaClimate.Orchard:
                        b.RoundBox(p+Vector3.Up*.08f,new(.63f,.16f,.36f),.02f,Hull);
                        for(int n=-1;n<=1;n++)b.Sphere(p+new Vector3(n*.18f,.22f,0),new(.11f,.16f,.11f),n==0?dye:Honey);
                        break;
                    case SeaClimate.Shelf:
                        b.RoundBox(p+Vector3.Up*.11f,new(.57f,.29f,.32f),.09f,Bone);
                        b.RoundBox(p+Vector3.Up*.26f,new(.09f,.04f,.31f),.01f,Hull);
                        break;
                    case SeaClimate.Loom:
                        b.Tube([p+new Vector3(-.26f,.15f,0),p+new Vector3(.28f,.15f,0)],.14f,i%2==0?dye:Bone);
                        break;
                    case SeaClimate.Sleep:
                    case SeaClimate.Choir:
                        b.RoundBox(p+Vector3.Up*.10f,new(.65f,.12f,.34f),.02f,Iron);
                        b.RoundBox(p+Vector3.Up*.20f,new(.59f,.13f,.31f),.045f,i==0?Bone:dye);
                        break;
                    case SeaClimate.Court:
                        b.RoundBox(p+Vector3.Up*.12f,new(.46f,.21f,.35f),.018f,Hull);
                        b.RoundBox(p+Vector3.Up*.24f,new(.50f,.04f,.37f),.018f,dye);
                        break;
                    default:
                        b.Crystal(p+Vector3.Up*.22f,new(.19f,.25f,.17f),dye);
                        b.Ring(p+Vector3.Up*.10f,.23f,.035f,Iron);
                        break;
                }
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
