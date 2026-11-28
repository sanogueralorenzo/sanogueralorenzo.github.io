using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class SeaLandmarks
{
    static readonly Dictionary<SeaClimate,ArrayMesh> cache=[];
    public static MeshInstance3D Float(SeaCountry country)
    {
        if(!cache.TryGetValue(country.Climate,out var mesh))
        {
            var b=new ActorGeometry();
            var dye=new Color(country.Accent);
            var shade=new Color(country.Shadow);
            var brass=new Color("d9a965");
            var cream=new Color("ffe9b3");
            switch(country.Climate)
            {
                case SeaClimate.Cinder:
                    b.Sphere(new(0,.12f,0),new(.72f,.29f,.63f),shade);
                    b.Tube([new(0,.17f,0),new(0,.65f,0),new(0,.89f,0)],[.51f,.40f,.24f],dye);
                    b.Ring(new(0,.85f,0),.26f,.052f,brass);
                    b.Sphere(new(0,.83f,0),new(.18f,.066f,.18f),new("ffc170"));
                    break;
                case SeaClimate.Delta:
                    b.RoundBox(new(0,.11f,0),new(.83f,.31f,.71f),.085f,shade);
                    for(int i=0;i<8;i++)
                    {
                        float a=i*Mathf.Tau/8;
                        var p=new Vector3(MathF.Cos(a)*.47f,.65f+MathF.Sin(a)*.47f,0);
                        b.Tube([new(0,.65f,0),p],.04f,brass);
                        b.RoundBox(p,new(.14f,.14f,.39f),.026f,dye);
                    }
                    break;
                case SeaClimate.Orchard:
                    b.Tube([new(0,-.06f,0),new(-.14f,.64f,.10f),new(.10f,1.11f,0)],[.13f,.10f,.06f],shade);
                    for(int i=0;i<5;i++)
                    {
                        float a=i*Mathf.Tau/5;
                        var p=new Vector3(MathF.Cos(a)*.42f,1.12f+MathF.Sin(a)*.10f,MathF.Sin(a)*.32f);
                        b.Tube([new(0,.78f,0),p],.044f,shade);
                        b.Sphere(p,new(.27f,.12f,.21f),new("659960"));
                        b.Sphere(p+Vector3.Down*.15f,new(.105f,.16f,.105f),dye);
                    }
                    break;
                case SeaClimate.Shelf:
                    for(int i=-1;i<=1;i++)
                        b.Crystal(new(i*.23f,.16f,.12f*MathF.Abs(i)),new(.27f,.23f+(1-MathF.Abs(i))*.39f,.31f),i==0?cream:dye);
                    break;
                case SeaClimate.Loom:
                    b.RoundBox(new(0,.08f,0),new(.82f,.27f,.58f),.08f,shade);
                    b.Tube([Vector3.Zero,new(0,1.16f,0)],.065f,brass);
                    for(int i=0;i<4;i++)
                    {
                        float a=i*Mathf.Pi/2;var p=new Vector3(MathF.Cos(a),MathF.Sin(a),0);var across=new Vector3(-p.Y,p.X,0);
                        var hub=new Vector3(0,1.09f,0);
                        b.Polygon([hub+p*.11f,hub+p*.62f,hub+p*.56f+across*.19f],i%2==0?cream:dye,Vector3.Back);
                    }
                    break;
                case SeaClimate.Choir:
                    for(int i=-2;i<=2;i++)
                    {
                        var p=new Vector3(i*.18f,.025f,MathF.Sin(i)*.13f);
                        b.Tube([p,p+new Vector3(i*.06f,.48f+.18f*(2-Math.Abs(i)),0)], [.13f,.09f],i%2==0?dye:shade);
                        b.Ring(p+new Vector3(i*.06f,.48f+.18f*(2-Math.Abs(i)),0),.09f,.026f,cream);
                    }
                    break;
                case SeaClimate.Court:
                    b.RoundBox(new(0,.13f,0),new(.82f,.31f,.67f),.075f,shade);
                    for(int i=0;i<3;i++)
                    {
                        b.RoundBox(new(.03f*i,.34f+i*.16f,0),new(.68f,.14f,.48f),.024f,i%2==0?dye:brass);
                        b.RoundBox(new(.03f*i,.34f+i*.16f,.245f),new(.52f,.085f,.019f),.009f,cream);
                    }
                    break;
                default:
                    b.Ring(new(0,.18f,0),.44f,.065f,brass);
                    for(int i=0;i<4;i++)
                    {
                        float a=Mathf.Pi/4+i*Mathf.Pi/2;
                        b.Crystal(new(MathF.Cos(a)*.38f,.26f,MathF.Sin(a)*.38f),new(.09f,.21f,.09f),dye);
                    }
                    b.Tube([new(0,.12f,0),new(0,.84f,0)],.045f,shade);
                    b.Crystal(new(0,.83f,0),new(.18f,.32f,.18f),cream);
                    break;
            }
            cache[country.Climate]=mesh=b.Mesh(DioramaSurface.Material);
        }
        return new(){Mesh=mesh};
    }
}
