using Godot;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    public static Node3D BoardingParty(int role)
    {
        string key=$"boarding-party-{role}";
        if(!Cache.TryGetValue(key,out var mesh))
        {
            var b=new ActorGeometry();Crewmate(b,Vector3.Zero,role,true);
            Color leather=new("6a4738"), linen=new("f0d8a1"), sea=new("287e80"),steel=new("b9d7d3"),scarlet=new("b94d3b");
            if(role==0)
            {
                b.Tube([new(.088f,.135f,-.079f),new(.105f,.162f,-.126f)],.012f,leather,7);
                b.Tube([new(.072f,.151f,-.112f),new(.107f,.151f,-.132f),new(.140f,.164f,-.129f)],.008f,Brass,7);
                Vector3 h=new(.105f,.159f,-.126f),tip=new(.17f,.235f,-.267f),edge=new(.143f,.188f,-.213f);
                b.Polygon([h,edge,tip,new(.125f,.185f,-.210f)],steel,Vector3.Up);
                b.Tube([h,edge,tip],[.007f,.008f,.002f],linen,6);
                foreach(float side in new[]{-1f,1f})
                {
                    var a=new Vector3(side*.016f,.154f,.035f);var c=new Vector3(side*.087f,.056f,.089f);
                    b.Polygon([a,new(side*.05f,.143f,.038f),c,new(side*.018f,.067f,.083f)],new("31567d"),Vector3.Back);
                    b.Tube([a,c],.004f,Brass,5);
                }
                b.Sphere(new(-.064f,.160f,.043f),new(.017f,.021f,.016f),Brass);
            }
            else if(role==1)
            {
                for(int i=0;i<3;i++)b.Ring(new(0,.114f+i*.012f,.044f),.052f,.006f,linen);
                b.Tube([new(-.055f,.112f,-.037f),new(-.097f,.156f,-.11f),new(-.117f,.174f,-.169f)],[.011f,.011f,.009f],leather,7);
                b.Tube([new(-.117f,.174f,-.169f),new(-.133f,.160f,-.191f),new(-.157f,.164f,-.190f),new(-.169f,.188f,-.173f)],[.009f,.013f,.012f,.002f],steel,7);
                for(int i=0;i<3;i++){var p=new Vector3(-.057f+i*.024f,.135f-i*.011f,.034f);b.Tube([p,p+new Vector3(.022f,-.017f,.015f)],.008f,sea,6);}
                b.Polygon([new(.031f,.128f,.047f),new(.063f,.119f,.044f),new(.104f,.094f,.096f),new(.084f,.095f,.100f),new(.064f,.079f,.113f)],scarlet,Vector3.Up);
            }
            else
            {
                b.Tube([new(-.11f,.130f,-.01f),new(-.056f,.159f,-.044f),new(.057f,.148f,-.087f)],[.023f,.021f,.015f],leather,7);
                b.Tube([new(-.021f,.171f,-.059f),new(.092f,.172f,-.128f),new(.145f,.179f,-.166f)],[.019f,.018f,.031f],Brass,8);
                b.Tube([new(.145f,.179f,-.166f),new(.149f,.179f,-.169f)],.022f,new("3d464d"),8);
                b.RoundBox(new(.018f,.126f,.046f),new(.068f,.083f,.035f),.006f,scarlet);
                b.Polygon([new(-.044f,.198f,.020f),new(.043f,.195f,.032f),new(.073f,.136f,.091f),new(.020f,.135f,.070f),new(-.062f,.152f,.059f)],scarlet,Vector3.Back);
                b.Tube([new(-.041f,.19f,.037f),new(.05f,.154f,.083f)],.005f,linen,5);
            }
            b.Scale(Vector3.One*3.05f);mesh=b.Mesh(Material);Cache[key]=mesh;
        }
        return Instance(mesh,key);
    }
    public static MeshInstance3D Veil(Node3D actor)
    {
        var body=actor.GetChild<MeshInstance3D>(0);
        var mesh=new MeshInstance3D{Mesh=body.Mesh,MaterialOverride=new ShaderMaterial{Shader=GD.Load<Shader>("res://source/presentation/boarding-silhouette.gdshader"),RenderPriority=3},CastShadow=GeometryInstance3D.ShadowCastingSetting.Off};
        body.AddChild(mesh);return mesh;
    }
}
