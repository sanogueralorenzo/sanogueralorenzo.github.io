using Godot;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    public static Node3D NellSpindle()
    {
        const string key = "nell-spindle";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var body = new ActorGeometry();
            Crewmate(body,Vector3.Zero,2);
            Vector3[] Hem(float y, float width, float depth)
            {
                return [new(-width,y,-depth*.60f),new(0,y,-depth),new(width,y,-depth*.60f),
                    new(width,y,depth),new(-width,y,depth)];
            }
            Color wool = new("544475");
            body.Loft([Hem(.054f,.083f,.046f), Hem(.11f,.068f,.042f), Hem(.207f,.050f,.037f)],
                [wool,wool.Lightened(.10f)]);
            body.Tube([new(-.049f,.199f,-.029f),new(0,.175f,-.046f),new(.049f,.199f,-.029f)],
                .005f,new("daa65f"),5);
            body.RoundBox(new(.067f,.118f,-.051f),new(.062f,.082f,.018f),.005f,new("8b593c"));
            body.RoundBox(new(.066f,.118f,-.062f),new(.060f,.009f,.005f),.001f,new("dcad62"));
            body.Tube([new(-.077f,.006f,-.063f),new(-.077f,.204f,-.069f),new(-.067f,.213f,-.069f)],
                .007f,new("79573f"),7);
            body.Scale(Vector3.One * 2.85f);
            Cache[key] = mesh = body.Mesh(Material);
        }
        return Instance(mesh,key);
    }
}
