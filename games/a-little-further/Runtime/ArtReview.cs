using Godot;
using Further.Core;
namespace Further;

// Explicit render inspection, separate from gameplay and never used as run validation.
public sealed class ArtReview(Node3D world,Run run,Camera3D camera,Action<string> capture,Action quit)
{
    float time;
    int previous=-1;
    readonly List<CharacterRig> cast=[];
    public void Step(float dt,bool ready)
    {
        if(!ready)return;time+=dt;int stage=(int)(time/2);
        var island=run.World.IslandAt(new(0,0));
        void Focus(Vector3 point){camera.LookAt(point);Flora.Update(point-Vector3.Up,camera.GlobalPosition);}
        if(stage<4)
        {
            var site=IslandLayout.Routes(island)[stage+1][^1]+island.Center;
            var orientation=new Basis(Vector3.Up,(island.Seed%7+stage+1)*.5f);
            Vector3 target=Art.At(site,World.Height(island,site))+orientation*new Vector3(-1.4f,.7f,-.75f);
            camera.Position=target+orientation*new Vector3(4,5,8);Focus(target);
        }
        else if(stage==4)
        {
            camera.Position=Art.At(island.Center,200)+new Vector3(30,0,-230);Focus(Art.At(island.Center,6));
        }
        else if(stage==5)
        {
            if(cast.Count==0)
            {
                for(int i=0;i<7;i++)
                {
                    Role? role=i==0?null:(Role)(i-1);var cat=(CharacterRig)Art.Pirate(world,role is Role r?Game.RoleColor(r):new Color("304b58"),i==0?1:.85f,role);
                    var p=island.Shrine+new System.Numerics.Vector2((i-3)*1.65f,4);cat.Position=Art.At(p,World.Height(island,p));cast.Add(cat);
                }
            }
            foreach(var cat in cast)cat.Step(dt,0);
            var center=cast[3].Position+Vector3.Up*.8f;camera.Fov=60;camera.Position=center+new Vector3(0,5.5f,10);Focus(center);
        }
        else{quit();return;}
        if(time%2>.8f && previous!=stage){capture(stage<4?$"art-site-{stage+1}":stage==4?"art-island":"art-characters");previous=stage;}
    }
}
