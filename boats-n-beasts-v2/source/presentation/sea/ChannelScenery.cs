using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class ChannelScenery
{
    static readonly Dictionary<(SeaClimate,bool,string),ArrayMesh> meshes=[];
    public static Node3D Make(SeaCountry country,ChannelBank bank)
    {
        var key=(country.Climate,bank.Breakable,country.Accent);
        if(!meshes.TryGetValue(key,out var mesh))
        {
            var b=new ActorGeometry();
            Color earth=new(country.Shadow), tint=new(country.Accent),wood=new("956746"),brass=new("ecc57d"),chalk=new("f4e1bf");
            if(country.Climate>=SeaClimate.Salt)WalkingScenery.Draw(b,country,bank:true);
            else switch(country.Climate)
            {
                case SeaClimate.Cinder:
                    for(int j=0;j<5;j++)
                    {
                        float z=-.84f+j*.42f, height=.21f+(j%3)*.19f;
                        b.Tube([new(0,-.06f,z),new(0,height,z)],[.48f,.32f],j%2==0?earth:tint,6);
                        b.Ring(new(0,height,z),.30f,.026f,wood);
                    }
                    break;
                case SeaClimate.Delta:
                    for(int i=-1;i<=1;i++)
                        b.Tube([new(i*.22f,.09f,-1.12f),new(i*.20f,.16f,.13f),new(i*.24f,.08f,1.10f)],.14f,wood);
                    for(int i=0;i<9;i++)
                    {
                        float x=.21f*MathF.Sin(i*2.3f),z=-.9f+i*.21f;
                        b.Tube([new(x,.12f,z),new(x+.12f,.6f+.21f*MathF.Sin(i),z+.03f)],[.038f,.013f],tint);
                    }
                    break;
                case SeaClimate.Orchard:
                    b.Tube([new(-.08f,.08f,-1.05f),new(.19f,.28f,-.1f),new(-.13f,.13f,1.02f)],[.21f,.31f,.13f],wood);
                    for(int j=0;j<5;j++)
                    {
                        var p=new Vector3((j%2==0?-1:1)*.32f,.62f,-.75f+j*.34f);
                        b.Tube([new(0,.18f,p.Z+.15f),p],.068f,wood);
                        b.Sphere(p,new(.31f,.10f,.21f),new("72905b"));
                        b.Sphere(p+Vector3.Down*.15f,new(.11f,.17f,.11f),tint);
                    }
                    break;
                case SeaClimate.Shelf:
                    for(int j=0;j<4;j++)
                    {
                        var p=new Vector3(MathF.Sin(j*3)*.19f,.13f,-.77f+j*.47f);
                        b.Crystal(p,new(.51f,.32f+(j%2)*.21f,.40f),j%2==0?tint:chalk);
                    }
                    break;
                case SeaClimate.Loom:
                    foreach(int i in new[]{-1,1})
                    {
                        b.Sphere(new(0,.07f,i*.90f),new(.32f,.23f,.27f),wood);
                        b.Tube([new(0,.12f,i*.9f),new(0,i<0?1.1f:.61f,i*.9f)],.063f,wood);
                    }
                    b.Polygon([new(0,1.07f,-.90f),new(0,.60f,.9f),new(-.08f,.33f,.60f),new(-.16f,.28f,-.17f),new(-.06f,.58f,-.9f)],tint,Vector3.Left);
                    b.Tube([new(0,1.07f,-.9f),new(.03f,.69f,0),new(0,.6f,.9f)],.035f,chalk);
                    break;
                case SeaClimate.Choir:
                    b.Sphere(new(0,.03f,0),new(.38f,.18f,1.05f),earth);
                    for(int j=0;j<7;j++)
                    {
                        float z=-.85f+j*.29f,x=(j%2==0?-.23f:.17f);
                        b.Tube([new(0,.12f,z),new(x,.4f,z),new(x*1.23f,.53f+(j%3)*.13f,z)],[.17f,.13f,.087f],tint);
                    }
                    break;
                case SeaClimate.Court:
                    b.RoundBox(new(0,.09f,0),new(.76f,.28f,2.14f),.075f,wood);
                    for(int j=0;j<4;j++)
                    {
                        b.RoundBox(new(.07f*MathF.Sin(j),.28f+j*.12f,0),new(.71f,.11f,1.53f-.15f*j),.025f,j%2==0?earth:tint);
                        b.RoundBox(new(.35f,.28f+j*.12f,0),new(.035f,.07f,1.3f-j*.14f),.009f,chalk);
                    }
                    break;
                default:
                    b.Tube([new(0,.08f,-1),new(.09f,.18f,-.19f),new(-.10f,.09f,1.02f)],[.19f,.22f,.12f],earth);
                    b.Tube([new(-.33f,.14f,-.44f),new(.35f,.54f,.13f)],.093f,wood);
                    b.Crystal(new(0,.48f,-.12f),new(.19f,.47f,.21f),tint);
                    break;
            }
            if(bank.Breakable)
            {
                b.RoundBox(new(0,.29f,-.76f),new(.28f,.14f,.30f),.028f,wood);
                b.Ring(new(0,.40f,-.76f),.18f,.041f,brass);
                b.Crystal(new(0,.43f,-.76f),new(.09f,.14f,.09f),brass);
            }
            meshes[key]=mesh=b.Mesh(DioramaSurface.Material);
        }
        return new MeshInstance3D {Mesh=mesh,Scale=new(bank.Width/46,1,bank.HalfSpan/100),
            Rotation=new(0,-MathF.Atan2(bank.Axis.X,-bank.Axis.Y),0)};
    }
}
