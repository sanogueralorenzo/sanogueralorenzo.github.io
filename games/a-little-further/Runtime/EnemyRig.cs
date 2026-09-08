using Godot;
namespace Further;

public partial class EnemyRig : Node3D
{
    Node3D body=null!,leftLeg=null!,rightLeg=null!,swordArm=null!;
    static Node3D Joint(Node3D parent,Vector3 p){var n=new Node3D{Position=p};parent.AddChild(n);return n;}
    static void Bone(Node3D root,Vector3 p,float length,float radius,Color color)
    {
        Art.Mesh(root,new CapsuleMesh{Radius=radius,Height=length,RadialSegments=10,Rings=4},p,color);
    }
    public void Build(int kind)
    {
        Color bone=new("c8bfa2"),cloth=new(kind==1?"3a4556":"395c59"),leather=new("433a32");
        body=Joint(this,new(0,.78f,0));
        // Retain the recovered Megabonk skull, with a fuller articulated silhouette.
        Art.Source(body,"skull",new(0,.65f,.06f),.62f).MaterialOverride=Art.Material(bone);
        foreach(float x in new[]{-.12f,.12f})
        {
            var eye=Art.Sphere(body,new(x,1.02f,.30f),.07f,new("273337"));eye.Scale=new(1,.9f,.35f);
        }
        var mouth=Art.Sphere(body,new(0,.83f,.31f),.10f,new("273337"));mouth.Scale=new(1,.24f,.22f);
        Bone(body,new(0,.23f,0),.67f,.20f,cloth);
        Bone(body,new(-.15f,.27f,.16f),.54f,.065f,bone);
        Bone(body,new(.15f,.27f,.16f),.54f,.065f,bone);
        var coat=new SurfaceTool();coat.Begin(Mesh.PrimitiveType.Triangles);
        for(int i=0;i<12;i++)
        {
            Vector3 Point(int j,bool hem){float a=j*Mathf.Tau/12;float radius=hem?.39f:.24f;return new(Mathf.Sin(a)*radius,hem?-.30f+(j%3)*.045f:.45f,Mathf.Cos(a)*radius);}
            foreach(var p in new[]{Point(i,false),Point(i+1,true),Point(i,true),Point(i,false),Point(i+1,false),Point(i+1,true)})coat.AddVertex(p);
        }
        coat.GenerateNormals();body.AddChild(new MeshInstance3D{Mesh=coat.Commit(),MaterialOverride=Art.Material(cloth)});
        Art.Cylinder(body,new(0,-.01f,0),.29f,.11f,leather);
        Art.Sphere(body,new(0,-.01f,.3f),.065f,Art.Gold);
        leftLeg=Joint(this,new(-.17f,.79f,0));rightLeg=Joint(this,new(.17f,.79f,0));
        foreach(var leg in new[]{leftLeg,rightLeg})
        {
            Bone(leg,new(0,-.28f,0),.52f,.075f,bone);
            var boot=Art.Mesh(leg,new CapsuleMesh{Radius=.11f,Height=.33f,RadialSegments=10},new(0,-.64f,.055f),leather);boot.RotationDegrees=new(70,0,0);
        }
        swordArm=Joint(body,new(-.33f,.48f,0));
        Bone(swordArm,new(-.035f,-.27f,0),.57f,.066f,bone);
        var hand=Joint(swordArm,new(-.04f,-.56f,.03f));
        Art.Sphere(hand,Vector3.Zero,.087f,bone);
        var blade=Art.Mesh(hand,new PrismMesh{Size=new(.085f,.68f,.035f)},new(0,0,.37f),new("a2b3ac"));blade.RotationDegrees=new(90,0,-12);
        Art.Cylinder(hand,new(0,0,.1f),.14f,.035f,Art.Gold).RotationDegrees=new(90,0,0);
        Bone(body,new(.34f,.19f,0),.55f,.075f,bone);
        // Folded cloth cap instead of the old rectangular hat slabs.
        var cap=Art.Mesh(body,new SphereMesh{Radius=.32f,Height=.22f,RadialSegments=12,Rings=6},new(0,1.18f,.02f),kind==1?new("293541"):new("984d40"));cap.Scale=new(1,.65f,1.15f);
        if(kind==1)
        {
            Bone(body,new(.45f,.12f,.1f),.83f,.20f,new("6b7069"));
            Art.Sphere(body,new(.4f,.53f,0),.27f,new("6b7069"));
        }
    }
    public void Step(float time,float windup)
    {
        leftLeg.Rotation=new(MathF.Sin(time*7)*.42f,0,0);rightLeg.Rotation=new(-MathF.Sin(time*7)*.42f,0,0);
        body.Position=new(0,.78f+MathF.Abs(MathF.Sin(time*7))*.025f,0);
        swordArm.Rotation=new(windup>0?-2.1f:MathF.Sin(time*7)*.2f,0,windup>0?-.3f:.08f);
    }
}
