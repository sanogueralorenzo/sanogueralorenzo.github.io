using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class BluewaterCoast
{
    public static Color Water(SeaClimate climate)=>new(climate switch
    {
        SeaClimate.Cinder=>"117f83", SeaClimate.Delta=>"377f73", SeaClimate.Orchard=>"306e78", SeaClimate.Shelf=>"438f9b",
        SeaClimate.Salt=>"488b82",SeaClimate.Bottle=>"2d9585",SeaClimate.Wax=>"3a847a",SeaClimate.Sleep=>"487a7b",
        SeaClimate.Tin=>"3b7689",SeaClimate.Drum=>"337e81",SeaClimate.Pitch=>"397678",SeaClimate.Calving=>"4c9a90",
        SeaClimate.Loom=>"257a81", SeaClimate.Choir=>"206c78", SeaClimate.Court=>"437679", _=>"236f83"
    });

    public static Node3D? Build(Place place,SeaCountry style,bool departure)
    {
        if(!OceanWorld.IsSolid(place))return null;
        var root=new Node3D();
        var b=new ActorGeometry(); var rng=new SeedRandom(place.Style);
        float radius=Math.Max(.25f,place.Radius*.01f);
        int steps=radius<1?18:48;
        var pale=new Color(style.Accent);var dark=new Color(style.Shadow);
        Color earth=new(style.Climate switch
        {
            SeaClimate.Cinder=>"ad705b",SeaClimate.Delta=>"877b55",SeaClimate.Orchard=>"94725c",
            SeaClimate.Shelf=>"dfebde",SeaClimate.Salt=>"e0c9b4",SeaClimate.Bottle=>"b78a68",SeaClimate.Tin=>"9694a3",SeaClimate.Pitch=>"776977",SeaClimate.Calving=>"c8ae95",SeaClimate.Choir=>"a98187",SeaClimate.Court=>"746579",_=>"a88b73"
        });
        Color green=new(style.Climate switch
        {
            SeaClimate.Orchard=>"687f54",SeaClimate.Salt=>"dfc6ac",SeaClimate.Bottle=>"739b72",SeaClimate.Sleep=>"8c9e85",SeaClimate.Wax=>"b4a468",SeaClimate.Tin=>"8f91a0",SeaClimate.Pitch=>"8f7d6c",SeaClimate.Calving=>"91aa8b",SeaClimate.Delta=>"809354",SeaClimate.Shelf=>"b9d3d5",
            SeaClimate.Cinder=>"a87459",SeaClimate.Loom=>"84976f",SeaClimate.Court=>"776a81",_=>"8a9285"
        });
        Vector3[] Ring(float scale,float height,float fold)
        {
            var ring=new Vector3[steps];
            for(int i=0;i<steps;i++)
            {
                float a=i*Mathf.Tau/steps;
                var p=place.Shape?.Point(a)??new System.Numerics.Vector2(MathF.Cos(a)*place.Radius,MathF.Sin(a)*place.Radius);
                float relief=(.5f+.5f*MathF.Sin(a*4+place.Style%9))*fold;
                ring[i]=new(p.X*.01f*scale,height+relief,p.Y*.01f*scale);
            }
            return ring;
        }
        var shore=Ring(1.04f,.035f,0);var surf=Ring(1.23f,.008f,0);
        float top=Math.Min(.58f,.12f+radius*.11f);
        var crown=Ring(.70f,top,.12f);
        b.Loft([surf, Ring(1.13f,.015f,0),Ring(1.055f,.027f,0),shore,crown],
            [new("49a89e"),new("72c9b9"),new("e0e4c4"),earth]);
        b.Polygon(crown,green,Vector3.Up);
        for(int j=0;j<(radius<1?2:7);j++)
        {
            float angle=rng.Range(0,Mathf.Tau);var q=place.Shape?.Point(angle);
            Vector3 p=q.HasValue?new(q.Value.X*.0098f,0,q.Value.Y*.0098f):new(radius*MathF.Cos(angle),0,radius*MathF.Sin(angle));
            float rockSize=Math.Clamp(radius*.12f,.12f,.52f)*rng.Range(.7f,1.4f);
            b.Sphere(p,new(rockSize,.8f*rockSize,rockSize*.78f),j%3==0?pale:earth);
        }
        if(departure)
        {
            var pier=shore[steps/10];var away=new Vector3(pier.X,0,pier.Z).Normalized();
            var across=away.Cross(Vector3.Up);
            for(int i=0;i<8;i++)
            {
                var center=pier+away*(i*.13f);
                b.Tube([center-across*.31f+Vector3.Up*.12f,center+across*.31f+Vector3.Up*.12f],.071f,new("c79b73"),5);
            }
        }
        root.AddChild(new MeshInstance3D{Mesh=b.Mesh(DioramaSurface.Material)});
        int count=place.Kind==PlaceKind.Rock?1:Math.Clamp((int)radius,2,7);
        for(int i=0;i<count;i++)
        {
            float a=rng.Range(0,Mathf.Tau),fraction=i==0?0:rng.Range(.28f,.62f);
            var raw=place.Shape?.Point(a)??new System.Numerics.Vector2(MathF.Cos(a)*place.Radius,MathF.Sin(a)*place.Radius);
            var prop=i==0&&departure?BluewaterPort.Make(style):SeaLandmarks.Float(style);
            prop.Position=new(raw.X*.01f*fraction,top+.02f,raw.Y*.01f*fraction);
            float size = i==0?Math.Clamp(radius*.74f,departure?.86f:.45f,departure?1.58f:2.45f):Math.Clamp(radius*.36f,.34f,1.13f);
            prop.Scale=Vector3.One*size;
            prop.Rotation=new(0,i==0?.18f:rng.Range(0,Mathf.Tau),0);
            root.AddChild(prop);
        }
        return root;
    }
}
