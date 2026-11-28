using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class UnderwayRun
{
    float volleyWait;
    public void Tick(float dt,Vector2 move,bool cut,bool dodge)
    {
        if(Surface!=null||Lost||Won||ChartOpen)return;
        Room.Rail?.Tick(dt);Clock+=dt;Swing=Cool(Swing,dt);Hook=Cool(Hook,dt);Flash=Cool(Flash,dt);HookWait=Cool(HookWait,dt);DodgeWait=Cool(DodgeWait,dt);Dash=Cool(Dash,dt);Hurt=Cool(Hurt,dt);cutWait=Cool(cutWait,dt);safe=Cool(safe,dt);volleyWait=Cool(volleyWait,dt);MessageClock=Cool(MessageClock,dt);
        if(move.LengthSquared()>1)move=Unit(move);
        if(move.LengthSquared()>.01f)Heading=move;
        if(dodge&&DodgeWait==0){Dash=.20f;DodgeWait=Math.Max(.52f,1.27f-.12f*Boots+(Outfit==Loadout.Broadside?.20f:0));dashDirection=Unit(Heading);safe=.30f;}
        float speed=Room.Trial==UnderTrial.Cradle&&Room.Step is 2 or 3&&!Room.Cleared?2.16f:2.83f;
        var delta=(Dash>0?dashDirection*8.1f:move*speed)*dt;
        Player=Move(Player,delta);
        var anchors=Room.Trial==UnderTrial.Keeper&&Room.Step==1;
        Vector2 lio=Room.Trial==UnderTrial.Dig&&Room.Lit[0]&&!Room.Cleared?Pad(RockIndex):anchors&&Room.Lit[0]?Pad(0):Room.Trial==UnderTrial.Capstan&&Room.Step>0&&!Room.Cleared?Pad(Room.Code[0]):Player-Heading*.53f+new Vector2(.38f,.19f);
        Vector2 gun=anchors&&Room.Lit[1]?Pad(1):Room.Trial==UnderTrial.Rescue&&Room.Step is 1 or 2?Pad(Room.Code[1]):Room.Trial==UnderTrial.Capstan&&Room.Step>1&&!Room.Cleared?Pad(Room.Code[1]):Player-Heading*.73f-new Vector2(.46f,.15f);
        Mate=Walkable(Vector2.Lerp(Mate,lio,Math.Min(1,dt*4.9f)));Vara=Walkable(Vector2.Lerp(Vara,gun,Math.Min(1,dt*4.5f)));
        if(cut&&cutWait==0&&Dash==0){cutWait=.40f;Swing=.22f;ToolWork(false,false,true);Slash();}
        for(int i=Room.Foes.Count-1;i>=0;i--)
        {
            var f=Room.Foes[i];if(f.Health<=0)
            {
                Attacks.RemoveAll(a=>a.Source==f);Room.Foes.RemoveAt(i);
                int count=f.Kind==YardBeast.Guardian?4:2;
                for(int k=0;k<count;k++){float a=k*MathF.Tau/count;Room.Drops.Add(Walkable(f.Position+new Vector2(MathF.Cos(a),MathF.Sin(a))*.36f));}
                if(f.Kind==YardBeast.Guardian){Room.Step=2;Say("The keeper yields. Retrieve the register on the archive desk.");}
                else if(Quiet&&Room.Trial==UnderTrial.Watch)Clear();
                continue;
            }
            MoveBeast(f,dt);
        }
        for(int i=Attacks.Count-1;i>=0;i--)
        {
            var a=Attacks[i];a.Age+=dt;if(!a.Fired&&a.Age>=a.Lead){a.Fired=true;if(a.Rush){a.Source.Rush=.30f;a.Source.RushTo=Walkable(a.Target);}}
            if(a.Fired&&!a.Hurt&&safe==0&&a.Contains(Player)){a.Hurt=true;Harm(a.Source.Kind==YardBeast.Guardian?2:1);}
            if(a.Age>=a.Lead+a.Active)Attacks.RemoveAt(i);
        }
        if(LoadLive&&safe==0&&(Near(LoadAt(0),.45f)||Near(LoadAt(1),.45f)))Harm(1);
        if(Room.Trial==UnderTrial.Rescue&&Room.Leads&&!Room.Cleared)
        {
            var target=Near(Winch,1.3f)?Winch:Player;
            var diff=target-Room.Escort;if(diff.Length()> .58f)Room.Escort+=Unit(diff)*Math.Min(diff.Length(),dt*(Outfit==Loadout.Lifeboat?3.18f:2.56f));
            if(Quiet&&Vector2.Distance(Room.Escort,Winch)<1.15f)Clear();
        }
        if(Room.Trial==UnderTrial.Cradle&&Room.Step>=2&&!Room.Cleared)
        {
            var d=Player-Room.Cargo;if(d.Length()>.68f)Room.Cargo+=Unit(d)*Math.Min(d.Length(),dt*2.65f);
        }
        for(int i=Room.Drops.Count-1;i>=0;i--)if(Near(Room.Drops[i],.94f)){Room.Drops.RemoveAt(i);silver++;}
    }
    Vector2 Move(Vector2 from,Vector2 delta)
    {
        if(Room.Trial!=UnderTrial.Freight||Room.Board is not {} board)return Walkable(from+delta);
        bool Trapped(Vector2 origin,Vector2 target,Vector2 obstacle,float radiusSquared)
        {
            float after=Vector2.DistanceSquared(target,obstacle);
            return after<radiusSquared&&after<Vector2.DistanceSquared(origin,obstacle);
        }
        bool Blocked(Vector2 origin,Vector2 target)=>
            board.Walls.Any(p=>Trapped(origin,target,p,.16f))||board.Blocks.Any(p=>Trapped(origin,target,board.At(p),.12f));
        var x=Walkable(from+new Vector2(delta.X,0));if(Blocked(from,x))x=from;
        var y=Walkable(x+new Vector2(0,delta.Y));return Blocked(x,y)?x:y;
    }
    void Harm(int amount){Vitality=Math.Max(0,Vitality-amount);Hurt=.29f;safe=.95f;if(Lost)Say("The rescue line brings the crew up with the silver they carried.");}
    void AddFoe(int slot,bool boss)
    {
        var r=Room;var kind=boss?YardBeast.Guardian:(YardBeast)((slot+(int)((uint)r.Seed%4))%4);
        int hp=boss?(Depth+1==Floors?99:65):kind==YardBeast.Porter?26:17;
        var pos=boss?new Vector2(0,-.40f):Pad((slot+1)%3)+new Vector2(slot==0?.51f:-.52f,-.29f);
        r.Foes.Add(new(Walkable(pos),kind,hp){Wait=.64f+slot*.24f});
    }
    void Slash()
    {
        var nearest=Room.Foes.MinBy(f=>Vector2.DistanceSquared(f.Position,Player));
        if(nearest!=null&&Near(nearest.Position,1.55f))Heading=Unit(nearest.Position-Player);
        foreach(var f in Room.Foes)
        {
            var d=f.Position-Player;if(d.Length()>1.48f||Vector2.Dot(Unit(d),Unit(Heading))<-.14f)continue;
            if(f.Kind==YardBeast.Guardian&&Room.Step==1)continue;
            bool guard=f.Kind==YardBeast.Porter&&f.Stagger==0&&Vector2.Dot(f.Heading,-Unit(d))>.42f;
            int baseHit=guard?2:f.Stagger>0?10:6;
            f.Health-=Math.Max(1,baseHit+Edge*2+(Outfit==Loadout.Broadside?3:Outfit==Loadout.Longline?-1:0));f.Hit=.17f;
        }
    }
    public void Cast()
    {
        if(ChartOpen||Lost||Won||HookWait>0)return;
        if(ToolWork(true,false,false))return;
        var f=Room.Foes.MinBy(f=>Vector2.DistanceSquared(f.Position,Player));if(f==null||!Near(f.Position,HookRange))return;
        bool counter=Attacks.RemoveAll(a=>a.Source==f&&!a.Fired)>0;Hook=.45f;HookEnd=f.Position;HookWait=Math.Max(1.6f,4.4f-.47f*Reel+(Outfit==Loadout.Longline?-.8f:0));
        if(f.Kind!=YardBeast.Guardian||Room.Step!=1){f.Health-=counter?11:3;f.Stagger=counter?1.24f:.55f;f.Hit=.18f;}
        if(f.Kind!=YardBeast.Guardian)f.Position=Walkable(Vector2.Lerp(f.Position,Player,.33f));
        if(counter)Say("Lio catches the wind-up. Strike before the guard recovers.");
    }
    public void Signal()
    {
        if(ChartOpen||Lost||Won)return;if(ToolWork(false,true,false))return;
        if(volleyWait>0)return;var f=Room.Foes.OrderBy(f=>f.Health).FirstOrDefault(f=>Near(f.Position,5.28f));if(f==null)return;
        Flash=.40f;volleyWait=5.2f;HookEnd=f.Position;
        if(f.Kind!=YardBeast.Guardian||Room.Step!=1){f.Health-=4+(Outfit==Loadout.Broadside?2:0);f.Hit=.18f;f.Stagger=Math.Max(.43f,f.Stagger);}
    }
    void MoveBeast(YardBeastState f,float dt)
    {
        f.Hit=Cool(f.Hit,dt);if(f.Stagger>0){f.Stagger=Cool(f.Stagger,dt);return;}
        if(f.Rush>0){f.Rush=Cool(f.Rush,dt);f.Position=Walkable(Vector2.Lerp(f.Position,f.RushTo,Math.Min(1,dt*13)));return;}
        bool boss=f.Kind==YardBeast.Guardian;
        if(boss&&Room.Step==0&&f.Health<=f.Maximum/2){Room.Step=1;f.Enraged=true;Attacks.Clear();Say("The keeper has latched its armor to both pillars. Lio can catch the left spring. Vara takes the right.");}
        var d=Player-f.Position;float clearance=boss?.84f:.43f;if(d.Length()<clearance)Player=Move(Player,Unit(d)*(clearance-d.Length()));
        if(Attacks.Any(a=>a.Source==f&&!a.Fired))return;f.Heading=Unit(d);
        f.Wait=Cool(f.Wait,dt);float desired=f.Kind switch{YardBeast.Slinger=>3.7f,YardBeast.Skater=>3.0f,YardBeast.Guardian=>2.70f,_=>1.23f};
        if(d.Length()>desired){f.Position=Walkable(f.Position+Unit(d)*dt*(boss?1.40f:1.63f));return;}
        if(f.Wait>0)return;
        f.Pattern++;
        void Hit(AttackShape type,Vector2 a,Vector2 b,float radius,float inner,float lead,bool rush=false)=>Attacks.Add(new(f,type,a,b,radius,inner,lead,.24f,rush));
        Vector2 p=f.Position,h=f.Heading,side=new(-h.Y,h.X);
        if(boss)
        {
            int pattern=(f.Pattern+Depth+Order.Tier)%5;float lead=f.Enraged?.88f:1.10f;
            switch(pattern)
            {
                case 0:Hit(AttackShape.Fan,p,p+h,2.86f,.20f,lead);break;
                case 1:Hit(AttackShape.Ring,p,p,3.03f,1.41f,lead);Hit(AttackShape.Disc,p,p,1.11f,0,lead+.50f);break;
                case 2:Hit(AttackShape.Lane,p,p+h*4.20f,.55f,0,lead,true);break;
                case 3:Hit(AttackShape.Disc,Player,Player,1.17f,0,lead);Hit(AttackShape.Disc,Player+side*1.22f,Player,1.05f,0,lead+.48f);break;
                default:Hit(AttackShape.Lane,Player-side*2.70f,Player+side*2.70f,.41f,0,lead);Hit(AttackShape.Lane,Player-h*2.26f,Player+h*2.26f,.38f,0,lead+.46f);break;
            }
            f.Wait=1.25f;return;
        }
        switch(f.Kind)
        {
            case YardBeast.Porter:Hit(AttackShape.Ring,p,p,1.80f,.42f,1.0f);break;
            case YardBeast.Slinger:Hit(AttackShape.Disc,Player,Player,.99f,0,.95f);break;
            case YardBeast.Skater:Hit(AttackShape.Lane,p,p+h*3.81f,.43f,0,.84f,true);break;
            default:Hit(AttackShape.Fan,p,p+h,1.53f,.12f,.74f);break;
        }
        f.Wait=1.23f;
    }
}
