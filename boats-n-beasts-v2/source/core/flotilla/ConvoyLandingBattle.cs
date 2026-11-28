using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class ConvoyLanding
{
    readonly Dictionary<YardAttack,MusterBoat> broadsides=[];
    float coverWait;
    public IReadOnlyDictionary<YardAttack,MusterBoat> BoatWarnings=>broadsides;
    void Spawn(YardBeast kind,Vector2 at)
    {
        int hp=kind switch{YardBeast.Guardian=>97,YardBeast.Porter=>31,YardBeast.Slinger=>18,_=>22};
        Foes.Add(new(Plan.Walkable(at),kind,hp){Wait=.9f+Foes.Count*.20f});
    }
    void Cut()
    {
        var hit=Foes.Where(f=>Near(f.Position,1.49f)).MinBy(f=>Vector2.DistanceSquared(Player,f.Position));if(hit==null)return;Heading=Unit(hit.Position-Player);
        foreach(var f in Foes)
        {
            var d=f.Position-Player;if(d.Length()>1.58f||Vector2.Dot(Heading,Unit(d))<-.12f)continue;
            if(f.Kind==YardBeast.Guardian&&HeldLines!=0)continue;
            f.Health-=(f.Stagger>0?10:7)+(Outfit==Loadout.Broadside?3:0);f.Hit=.18f;
        }
    }
    void Battle(float dt)
    {
        coverWait=Cool(coverWait,dt);
        if(Phase==MusterPhase.Guard&&coverWait==0&&Foes.Count>0)
        {
            int passengers=Boats.Sum(b=>b.Hull>0?b.People:0);
            if(passengers>0){var f=Foes.MinBy(f=>Vector2.DistanceSquared(f.Position,Player))!;f.Stagger=Math.Max(f.Stagger,.55f);if(f.Kind!=YardBeast.Guardian||HeldLines==0)f.Health-=Math.Min(5,passengers);coverWait=3.6f;}
        }
        for(int i=Foes.Count-1;i>=0;i--)
        {
            var f=Foes[i];
            if(f.Health<=0)
            {
                Attacks.RemoveAll(a=>a.Source==f);Foes.RemoveAt(i);Drops.Add(f.Position);if(f.Kind==YardBeast.Guardian){Silver+=6;Drops.Add(f.Position+new Vector2(.33f,0));}
                continue;
            }
            if(f.Kind==YardBeast.Guardian&&!commandTurn&&f.Health<=f.Maximum*.58f)
            {
                commandTurn=true;requiredLines=Math.Min(2,Alive);HeldLines=Boats.Where(b=>b.Hull>0).Sum(b=>1<<b.Index);
                f.Stagger=.58f;Attacks.Clear();Say($"{Order.Boss} hooks the pennants to its breastplate. Call the posted crews to shake the lines free.");
            }
            Enemy(f,dt);
        }
        for(int i=Attacks.Count-1;i>=0;i--)
        {
            var a=Attacks[i];a.Age+=dt;
            if(!a.Fired&&a.Age>=a.Lead)
            {
                a.Fired=true;if(a.Rush){a.Source.Rush=.26f;a.Source.RushTo=Plan.Walkable(a.Target);}
                if(broadsides.TryGetValue(a,out var b)&&b.Hull>0)
                {
                    if(b.Timbers>0){b.Timbers--;Say($"{b.Name}’s breastwork catches the shot.");}
                    else if(a.Contains(Player)){Say($"The captain intercepts the shot for {b.Name}.");}
                    else{b.Hull=Math.Max(0,b.Hull-2);Say(b.Hull==0?$"{b.Name} grounds on the bar. The other boats keep moving.":$"{b.Name} takes a hit. Hook the next wind-up or stand on its pennant.");}
                }
            }
            if(a.Fired&&!a.Hurt&&safe==0&&a.Contains(Player)){a.Hurt=true;Health=Math.Max(0,Health-(a.Source.Kind==YardBeast.Guardian?2:1));Hurt=.24f;safe=.97f;}
            if(a.Age>=a.Lead+a.Active)Attacks.RemoveAt(i);
        }
        foreach(var a in broadsides.Keys.Where(a=>!Attacks.Contains(a)).ToArray())broadsides.Remove(a);
        if(HeldLines!=0){HeldLines&=Boats.Where(b=>b.Hull>0).Sum(b=>1<<b.Index);requiredLines=Math.Min(requiredLines,brokenLines+System.Numerics.BitOperations.PopCount((uint)HeldLines));}
        if(Health<=0||Alive==0){Phase=MusterPhase.Lost;return;}
        if(Phase==MusterPhase.Guard&&Foes.Count==0){Phase=MusterPhase.Locks;Attacks.Clear();Silver+=2;Say("Lio and Vara take the heavy chains. Cross to their marked winches.");}
    }
    void Enemy(YardBeastState f,float dt)
    {
        f.Hit=Cool(f.Hit,dt);if(f.Stagger>0){f.Stagger=Cool(f.Stagger,dt);return;}
        if(f.Rush>0){f.Rush=Cool(f.Rush,dt);f.Position=Plan.Walkable(Vector2.Lerp(f.Position,f.RushTo,Math.Min(1,dt*14)));return;}
        bool boss=f.Kind==YardBeast.Guardian;
        var diff=Player-f.Position;float radius=boss?.91f:.49f;
        if(diff.Length()<radius)Player=Plan.Walkable(Player+Unit(diff)*(radius-diff.Length()));
        if(Attacks.Any(a=>a.Source==f&&!a.Fired))return;
        f.Heading=Unit(diff);float reach=f.Kind==YardBeast.Slinger?4.30f:boss?3.2f:1.42f;
        bool shipAttack=Phase==MusterPhase.Guard&&(f.Kind==YardBeast.Slinger||boss)&&(f.Pattern+1)%3==0;
        if(!shipAttack&&diff.Length()>reach)
        {
            f.PathUpdate=Cool(f.PathUpdate,dt);if(f.PathUpdate==0){f.Waypoint=Plan.Waypoint(f.Position,Player);f.PathUpdate=.22f;}
            f.Position=Plan.Walkable(f.Position+Unit(f.Waypoint-f.Position)*dt*(boss?1.77f:2.14f));return;
        }
        f.Wait=Cool(f.Wait,dt);if(f.Wait>0)return;f.Pattern++;f.Wait=boss?1.07f:1.24f;
        YardAttack Hit(AttackShape shape,Vector2 origin,Vector2 target,float r,float inner,float lead,bool rush=false)
        {var hit=new YardAttack(f,shape,origin,target,r,inner,lead,.23f,rush);Attacks.Add(hit);return hit;}
        if(shipAttack)
        {
            var live=Boats.Where(b=>b.Hull>0).ToArray();var b=live[(f.Pattern/3+District+f.Maximum)%live.Length];var p=Launch(b.Index);
            var a=Hit(AttackShape.Disc,p,p,1.24f,0,1.65f);broadsides[a]=b;Say($"Incoming on {b.Name}! Intercept at its pennant or catch the shooter’s wind-up.");return;
        }
        var pos=f.Position;var h=f.Heading;var side=new Vector2(-h.Y,h.X);
        if(boss)
        {
            int pattern=(f.Pattern+(int)Region.Climate)%5;float lead=f.Health<f.Maximum/2?.81f:1.12f;
            switch(pattern)
            {
                case 0:Hit(AttackShape.Ring,pos,pos,3.21f,1.34f,lead);break;
                case 1:Hit(AttackShape.Lane,pos,pos+h*4.5f,.61f,0,lead,true);break;
                case 2:Hit(AttackShape.Disc,Player,Player,1.28f,0,lead);Hit(AttackShape.Disc,Player+side*1.28f,Player,1.08f,0,lead+.47f);break;
                case 3:Hit(AttackShape.Fan,pos,pos+h,3.1f,.22f,lead);break;
                default:Hit(AttackShape.Lane,Player-side*2.55f,Player+side*2.55f,.44f,0,lead);Hit(AttackShape.Lane,Player-h*2.55f,Player+h*2.55f,.39f,0,lead+.48f);break;
            }
        }
        else if(f.Kind==YardBeast.Slinger)Hit(AttackShape.Disc,Player,Player,1.01f,0,.91f);
        else if(f.Kind==YardBeast.Porter)Hit(AttackShape.Ring,pos,pos,1.85f,.47f,.97f);
        else if(f.Kind==YardBeast.Skater)Hit(AttackShape.Lane,pos,pos+h*3.25f,.42f,0,.80f,true);
        else Hit(AttackShape.Fan,pos,pos+h,1.61f,.12f,.76f);
    }
}
