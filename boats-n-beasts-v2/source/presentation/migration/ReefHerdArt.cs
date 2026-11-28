using Godot;

namespace BoatsNBeasts;

internal static class ReefHerdArt
{
    static readonly Color[] Shell=[new("b4a36c"),new("71a88b"),new("dc995a"),new("9f91b0"),
        new("8ba5ad"),new("c78b68"),new("7e8582"),new("d3aa78")];
    internal static Node3D Calf(int dye,bool mother=false)
    {
        var b=new ActorGeometry();Color hide=Shell[dye%Shell.Length],moss=new("73985c"),iris=new("243a47");
        b.Sphere(new(0,.21f,.06f),new(.62f,.29f,.75f),hide.Darkened(.15f),11,7);
        b.Sphere(new(0,.43f,.11f),new(.58f,.37f,.65f),hide,9,5);
        b.Sphere(new(0,.61f,.13f),new(.47f,.18f,.50f),moss,9,5);
        for(int side=-1;side<=1;side+=2)
        {
            b.Tube([new(side*.39f,.17f,-.24f),new(side*.61f,.06f,-.33f),new(side*.73f,.09f,-.57f)], [.12f,.11f,.025f],hide,7);
            b.Tube([new(side*.39f,.16f,.45f),new(side*.55f,.05f,.62f),new(side*.58f,.07f,.79f)], [.11f,.1f,.026f],hide,7);
        }
        b.Sphere(new(0,.29f,-.64f),new(.31f,.22f,.35f),hide.Lightened(.09f),11,6);
        b.Sphere(new(0,.23f,-.86f),new(.235f,.12f,.17f),new("ddb68a"),10,5);
        for(int side=-1;side<=1;side+=2)
        {
            b.Sphere(new(side*.205f,.37f,-.825f),new(.071f,.075f,.054f),new("f7dc9a"),8,5);
            b.Sphere(new(side*.218f,.373f,-.858f),new(.041f,.051f,.027f),iris,7,4);
        }
        for(int i=0;i<7;i++)
        {
            float a=i*Mathf.Tau/7;
            b.Sphere(new(Mathf.Cos(a)*.44f,.49f,.10f+Mathf.Sin(a)*.47f),new(.115f,.105f,.14f),hide.Lightened((i%3)*.07f),7,4);
        }
        for(int i=0;i<(mother?3:1);i++)
        {
            var foot=new Vector3((i-1)*.18f+.10f,.68f,.15f+(i%2)*.17f);
            var top=foot+new Vector3(.07f,.33f+.08f*(dye%3),-.045f);
            b.Tube([foot,top],[.042f,.021f],new("9b6743"),7);
            for(int j=0;j<5;j++)
            {
                float a=j*Mathf.Tau/5+i;
                var ray=new Vector3(Mathf.Cos(a),0,Mathf.Sin(a));
                var cross=new Vector3(-ray.Z,0,ray.X)*.056f;
                var mid=top+ray*.145f+Vector3.Up*.068f;
                b.Polygon([top,mid+cross,top+ray*.30f-Vector3.Up*.05f,mid-cross],j%2==0?new("a9b95c"):moss,Vector3.Up);
            }
        }
        var root=new Node3D();root.AddChild(new MeshInstance3D{Mesh=b.Mesh(DioramaSurface.Material)});
        if(mother)root.Scale=Vector3.One*3.25f;
        return root;
    }
    internal static Node3D Kelp()
    {
        var b=new ActorGeometry();
        for(int j=0;j<15;j++)
        {
            float a=j*2.39f;
            var p=new Vector3(Mathf.Cos(a),0,Mathf.Sin(a))*(.19f+.43f*(j%5)/4);
            b.Tube([p,p+new Vector3(.04f,.14f,.06f),p+new Vector3(.14f,.19f,-.02f)],[.04f,.083f,.008f],j%2==0?new("79b46e"):new("51896a"),5);
        }
        var root=new Node3D();root.AddChild(new MeshInstance3D{Mesh=b.Mesh(DioramaSurface.Material)});return root;
    }
}
