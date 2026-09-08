using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Original art, drawn from polygons and lit, bevelled surfaces. No imported art or textures.
public sealed class ProceduralArt(Node2D canvas)
{
    static readonly Color Cream = new("ffe4ac"), Sand = new("e2c38a"), SandLight = new("ffe9b8"), SandShade = new("b3946b"), RockDark = new("525b56");
    static readonly Color Orange = new("f87929"), OrangeLight = new("ffab45"), OrangeDark = new("b84018"), Coral = new("dc654d"), CoralLight = new("ef9170"), CoralDark = new("963e36"), Ink = new("102944"), Metal = new("374454");
    static readonly Color Shadow = new(.01f, .075f, .09f, .4f);
    static readonly Color Teal = new("347f80"), TealDark = new("19545d"), TealLight = new("72b0a0"), Ochre = new("c7a24f"), OchreDark = new("8d743d");
    readonly Dictionary<uint, IslandMesh> islands = new();
    sealed record IslandMesh(Vector2[] Ring);
    void Poly(Vector2[] points, Color color) => canvas.DrawColoredPolygon(points, color);
    void Line(Vector2 a, Vector2 b, Color color, float width = 2) => canvas.DrawLine(a, b, color, width, true);
    void Ellipse(Vector2 p, Vector2 r, Color color)
    {
        var points = new Vector2[32]; for (int i = 0; i < points.Length; i++) { float a = i * Mathf.Tau / points.Length; points[i] = p + new Vector2(Mathf.Cos(a) * r.X, Mathf.Sin(a) * r.Y); } Poly(points, color);
    }
    Vector2[] Shift(Vector2[] points, Vector2 d) => points.Select(v => v + d).ToArray();
    void Prism(Vector2[] shape, float height, Color top, Color side, Color? rim = null)
    {
        var up = new Vector2(0, -height);
        for (int i = 0; i < shape.Length; i++)
        {
            int j = (i + 1) % shape.Length;
            var normal = (shape[j] - shape[i]).Orthogonal().Normalized();
            float light = Mathf.Clamp(.8f + normal.Dot(new(-.6f, -.8f)) * .25f, .5f, 1.05f);
            Poly([shape[i], shape[j], shape[j] + up, shape[i] + up], side * new Color(light, light, light, 1));
        }
        Poly(Shift(shape, up), top);
        if (rim != null) { var edges = Shift(shape, up).ToList(); edges.Add(edges[0]); canvas.DrawPolyline(edges.ToArray(), rim.Value, 1.4f, true); }
    }
    void Box(Vector2 p, Vector2 size, float height, Color top, Color side) => Prism([p, p + new Vector2(size.X, 0), p + size, p + new Vector2(0, size.Y)], height, top, side);
    Vector2[] Hull(float width, float length)
    {
        return [new(0,-length*.55f),new(width*.34f,-length*.37f),new(width*.49f,-length*.15f),new(width*.5f,length*.24f),new(width*.33f,length*.45f),new(-width*.33f,length*.45f),new(-width*.5f,length*.24f),new(-width*.49f,-length*.15f),new(-width*.34f,-length*.37f)];
    }
    public void Boat(Vector2 p, float height, float angle, BoatKind kind, float clock, int[]? weapons = null, bool flash = false, float aimAngle = 0, bool muzzle = false)
    {
        float s = height / 145; canvas.DrawSetTransform(p, angle, Vector2.One * s);
        bool tug = kind == BoatKind.Trawler; float width = tug ? 83 : 64;
        var hull = Hull(width, 139);
        Poly(Shift(hull, new(7, 9)), Shadow);
        Prism(hull, 3, Ink, Ink);
        Prism(Shift(Hull(width-3, 133),new(0,-4)), 7, Cream, SandShade, SandLight);
        Poly(Shift(Hull(width-16, 114), new(0,-11)), Ink);
        Poly(Shift(Hull(width-20, 110), new(0,-12)), new Color("bc915d"));
        for(int i=0;i<3;i++) Line(new(-width*.32f, -24+i*24),new(width*.32f,-24+i*24),new Color("c9a774"),1);
        // Gunwales, tie-off cleats and orange hull stripe.
        Line(new(-width*.43f,-22),new(-width*.43f,24),SandLight,3);
        Line(new(width*.43f,-22),new(width*.43f,24),Cream,3);
        for(int side=-1;side<=1;side+=2)for(int y=-29;y<=34;y+=63)
        { Ellipse(new(side*width*.4f,y),new(4,7),Ink);Line(new(side*width*.4f-4,y),new(side*width*.4f+4,y),Metal,2); }
        // Raised cabin, dark panoramic windows, bevelled orange roof.
        float cabinW=tug?48:35;
        Box(new(-cabinW/2,-16),new(cabinW,39),15,Cream, SandShade);
        Poly([new(-cabinW/2+3,10),new(-cabinW/2+3,20),new(cabinW/2-3,20),new(cabinW/2-3,10)],Ink);
        Line(new(-cabinW/2+5,12),new(cabinW/2-5,12),new Color("61939e"),2);
        Line(new(0,10),new(0,21),Cream,3);
        Poly([new(-cabinW/2,-31),new(cabinW/2,-31),new(cabinW/2-4,-11),new(-cabinW/2+4,-11)],SandLight);
        Poly([new(-cabinW/2+4,-29),new(cabinW/2-4,-29),new(cabinW/2-6,-13),new(-cabinW/2+6,-13)],Cream);
        Line(new(-cabinW/2,-31),new(cabinW/2,-31),new Color("ffcc72"),2);
        Box(new(-6,-25),new(12,8),3,SandLight,SandShade);
        Line(new(0,-27), new(0,-49), Ink, 2);
        Line(new(0,-45), new(12,-41), Cream, 2);
        if(tug)
        {
            for(int side=-1;side<=1;side+=2){Box(new(side*25-5,28),new(10,16),17,Metal,Ink);Ellipse(new(side*25,11),new(5,4),Ink);}
        }
        else { Line(new(-15,22),new(-16,43),Metal,2);Ellipse(new(-16,43),new(5,3),Cream); }
        if (weapons != null && weapons[0] > 0) Gun(new(0,-48),aimAngle,weapons[0] >= 3);
        if (muzzle && weapons != null && weapons[0] > 0)
        {
            int count=weapons!=null && weapons[0]>=3?2:1;
            var dir=Vector2.FromAngle(aimAngle-Mathf.Pi/2);
            for(int barrel=0;barrel<count;barrel++)
            {
                var at=new Vector2(0,-48)+dir*25+dir.Orthogonal()*(count==2?(barrel==0?-9:9):0);
                for(int i=0;i<3;i++){float a=i*Mathf.Tau/5;Spike(at,at+Vector2.FromAngle(a)*11,3,Cream);}
            }
        }
        if(weapons!=null && weapons[1]>0){Line(new(width*.34f,5),new(width*.34f,-21),Metal,5);Poly([new(width*.34f,-29),new(width*.34f-5,-18),new(width*.34f+5,-18)],Cream);}
        if(weapons!=null && weapons[2]>0){Ellipse(new(-width*.32f,22),new(9,8),Ink);Ellipse(new(-width*.32f,19),new(8,7),Metal);Ellipse(new(-width*.32f,17),new(4,4),Ink);}
        if(weapons!=null && weapons[3]>0){Box(new(width*.24f-5,27),new(10,12),5,Metal,Ink);for(int i=0;i<3;i++)Ellipse(new(width*.24f,23-i*3),new(6,2),new Color("69e1d3"));}
        if(flash)canvas.DrawPolyline(Shift(hull,new(0,-5)).Append(hull[0]+new Vector2(0,-5)).ToArray(),new Color("fff9e4"),3,true);
        canvas.DrawSetTransform(Vector2.Zero);
    }
    void Gun(Vector2 p, float angle, bool twin)
    {
        Ellipse(p+new Vector2(2,4),new(twin?17:12,10),Ink); Ellipse(p,new(twin?16:11,9),Cream); Ellipse(p+new Vector2(0,-3),new(twin?13:8,7),Metal);
        var d=Vector2.FromAngle(angle-Mathf.Pi/2); var side=d.Orthogonal();
        for(int i=0;i<(twin?2:1);i++)
        {
            var at=p+side*(twin?(i==0?-9:9):0);
            Poly([at-side*4,at+side*4,at+d*23+side*3,at+d*23-side*3],Ink);
            Line(at+d*4-side*1.5f,at+d*23-side*1.5f,new Color("748087"),2);
            Line(at+d*24-side*4,at+d*24+side*4,Metal,4);
        }
        Ellipse(p+new Vector2(-2,-4),new(3,2),new Color("626c72"));
    }
    public void Monster(Vector2 p, float height, EnemyKind kind, float clock, float facing=0, bool flash=false)
    {
        float scale=height/(kind==EnemyKind.Serpent?140:kind==EnemyKind.Leviathan?210:112);
        canvas.DrawSetTransform(p,kind == EnemyKind.Serpent ? facing-Mathf.Pi : 0,Vector2.One*scale);
        if(kind==EnemyKind.Serpent)Serpent(clock,facing,flash);
        else if(kind==EnemyKind.Puffer)Puffer(clock,flash);
        else if(kind==EnemyKind.Ray)Ray(clock,flash);
        else Crab(clock,kind==EnemyKind.Leviathan,flash);
        canvas.DrawSetTransform(Vector2.Zero);
    }
    void Ray(float clock, bool flash)
    {
        float flap = MathF.Sin(clock * 4) * 9;
        Color top = flash ? Cream : TealDark;
        var wing = new Vector2[] { new(-60, 10 + flap), new(-24,-18), new(0,-32), new(24,-18), new(60,10+flap), new(18,22), new(0,10), new(-18,22) };
        Poly(Shift(wing, new(5,9)), Shadow);
        Poly(wing, top);
        Poly([new(-60,10+flap),new(-24,-18),new(-35,8+flap*.5f)],Cream);
        Poly([new(60,10+flap),new(24,-18),new(35,8+flap*.5f)],Cream);
        Poly([new(0,-30),new(17,9),new(0,18),new(-17,9)],flash?Cream:Teal);
        Spike(new(0,8),new(8+MathF.Sin(clock*3)*8,65),4,TealDark);
        Eye(new(-9,-13),4); Eye(new(9,-13),4);
    }
    void Shell(Vector2 p,Vector2 radius,Color top,Color dark,int sides,uint seed)
    {
        var ring = Enumerable.Range(0, sides).Select(i => p + new Vector2(Mathf.Cos(i*Mathf.Tau/sides)*radius.X, Mathf.Sin(i*Mathf.Tau/sides)*radius.Y)).ToArray();
        Poly(Shift(ring,new(3,6)),Shadow);
        Poly(ring,dark);
        var crown = ring.Select(v => p + (v-p)*new Vector2(.92f,.78f) - new Vector2(0,radius.Y*.16f)).ToArray();
        Poly(crown,top);
        Poly([crown[sides/2],crown[(sides/2+1)%sides],crown[(sides*3/4)%sides],p+new Vector2(-radius.X*.12f,-radius.Y*.08f)],top.Lightened(.12f));
    }
    void Spike(Vector2 root,Vector2 tip,float width,Color color)
    {
        var side=(tip-root).Normalized().Orthogonal()*width;
        Poly([root-side,tip,root+side],color);Poly([root,tip,root+side],color.Darkened(.3f));Line(root-side,tip,color.Lightened(.18f),1);
    }
    void Leg(Vector2 a,Vector2 b,Vector2 c,float width)
    {
        var n=(b-a).Normalized().Orthogonal()*width;
        Poly([a-n,b-n*.5f,b+n*.5f,a+n],CoralDark);Poly([a-n,b-n*.5f,b,a],CoralLight);
        n=(c-b).Normalized().Orthogonal()*width*.6f;Poly([b-n,c,b+n],Coral);Line(b-n,c,CoralLight,1.5f);
    }
    void Eye(Vector2 p,float radius,bool angry=false)
    {
        Ellipse(p+new Vector2(1,2),new(radius+2,radius+1),CoralDark);Ellipse(p,new(radius,radius*.88f),Cream);
        Ellipse(p+new Vector2(1,1),new(radius*.56f,radius*.66f),Ink);Ellipse(p+new Vector2(-1,-2),new(radius*.2f,radius*.2f),Colors.White);
        if(angry)Poly([p+new Vector2(-radius,-radius),p+new Vector2(radius,-radius*.45f),p+new Vector2(radius,-radius*1.2f)],Coral);
    }
    void Crab(float clock,bool boss,bool flash)
    {
        float s=boss?1.65f:1;
        for(int side=-1;side<=1;side+=2)for(int i=0;i<3;i++)
        {
            float swing=MathF.Sin(clock*5+i*1.9f)*5;
            Leg(new(side*24*s,(-14+i*14)*s),new(side*(43+i*3)*s,(-23+i*19+swing)*s),new(side*(50+i*4)*s,(-10+i*20+swing)*s),5*s);
        }
        for(int i=0;i<5;i++)
        {float a=Mathf.Pi+i*Mathf.Pi/4;var root=new Vector2(Mathf.Cos(a)*31*s,Mathf.Sin(a)*24*s);Spike(root,root+new Vector2(Mathf.Cos(a)*12,Mathf.Sin(a)*15)*s,4*s,boss?Cream:Coral);}
        Shell(new(0,0),new(36*s,29*s),flash?Cream:Coral,CoralDark,10,72);
        if(boss)
        {
            Shell(new(0,-4*s),new(26*s,19*s),Metal,Ink,7,128);
            for(int i=-1;i<=1;i++)Spike(new(i*15*s,-13*s),new(i*22*s,-(i==0?54:41)*s),7*s,Cream);
            for(int side=-1;side<=1;side+=2)Spike(new(side*24*s,3*s),new(side*39*s,-5*s),5*s,Cream);
        }
        Eye(new(-13*s,17*s),7*s,boss);Eye(new(13*s,17*s),7*s,boss);
        Poly([new(-7*s,28*s),new(7*s,28*s),new(0,32*s)],Ink);
        for(int side=-1;side<=1;side+=2)
        {
            float sway=MathF.Sin(clock*3+side)*4;
            Leg(new(side*27*s,19*s),new(side*42*s,34*s),new(side*35*s,(46+sway)*s),7*s);
            var at=new Vector2(side*34*s,(48+sway)*s);
            Ellipse(at,new(14*s,16*s),CoralDark);
            Ellipse(at+new Vector2(-2*s,-2*s),new(12*s,14*s),flash?Cream:Coral);
            Poly([at+new Vector2(-11*s,3*s),at+new Vector2(-8*s,20*s),at+new Vector2(2*s,25*s),at+new Vector2(-1*s,10*s)],flash?Cream:Coral);
            Poly([at+new Vector2(7*s,0),at+new Vector2(14*s,14*s),at+new Vector2(5*s,24*s),at+new Vector2(7*s,11*s)],flash?Cream:CoralLight);
            if(boss){Spike(at+new Vector2(-3*s,14*s),at+new Vector2(7*s,19*s),4*s,Cream);}
        }
    }
    void Puffer(float clock,bool flash)
    {
        for(int i=0;i<10;i++){float a=i*Mathf.Tau/10;var root=new Vector2(Mathf.Cos(a)*32,Mathf.Sin(a)*31);Spike(root,root+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*11,4,Ochre);}
        Shell(new(0,0),new(37,35),flash?Cream:Ochre,OchreDark,12,391);
        Ellipse(new(0,13),new(27,17),SandLight);
        for(int i=0;i<3;i++) Ellipse(new(-19+i*17,-19+(i%2)*4),new(3,4),OchreDark);
        Eye(new(-11,-1),7); Eye(new(12,-1),7);
        Ellipse(new(1,15),new(5,4),Ink);
        Poly([new(-30,7),new(-46,13+MathF.Sin(clock*8)*3),new(-31,22)],Ochre);
        Poly([new(30,7),new(46,13-MathF.Sin(clock*8)*3),new(31,22)],Ochre);
    }
    void Serpent(float clock,float facing,bool flash)
    {
        // Continuous body planes avoid seams where the animated segments join.
        var path=new Vector2[15]; var upper=new Vector2[15]; var lower=new Vector2[15];
        for(int i=0;i<path.Length;i++)
        {
            float t=i/14f;
            path[i]=new((t-.5f)*130,MathF.Sin(t*6+clock*3)*14+(t-.5f)*20);
            float r=3+(1-t)*16;
            upper[i]=path[i]+new Vector2(0,-r); lower[i]=path[i]+new Vector2(0,r);
        }
        var body=upper.Concat(lower.Reverse()).ToArray();
        Poly(Shift(body,new(3,6)),Shadow);
        for(int i=2;i<14;i+=3) Spike(upper[i],upper[i]+new Vector2(8,-14),6,Coral);
        Poly(body,flash?Cream:TealDark);
        Poly(upper.Concat(path.Reverse()).ToArray(),flash?Cream:Teal);
        var belly=path.Select((v,i)=>v.Lerp(lower[i],.72f)).ToArray();
        Poly(path.Concat(belly.Reverse()).ToArray(),flash?Cream:TealLight);
        for(int i=2;i<13;i+=3) Line(path[i],belly[i],new Color(TealDark,.5f),1.5f);
        var head=path[0];
        Poly([head+new Vector2(-24,-1),head+new Vector2(-9,-19),head+new Vector2(17,-14),head+new Vector2(20,10),head+new Vector2(-9,18)],flash?Cream:Teal);
        Poly([head+new Vector2(-24,-1),head+new Vector2(-2,6),head+new Vector2(14,8),head+new Vector2(-9,18)],flash?Cream:TealLight);
        Line(head+new Vector2(-20,3),head+new Vector2(-3,9),Ink,2);
        Eye(head+new Vector2(-3,-8),5);
        Spike(head+new Vector2(11,-13),head+new Vector2(21,-29),5,Coral);
    }
    public void Island(Vector2 p,float radius,uint seed,bool harbor,float clock)
    {
        if(!islands.TryGetValue(seed,out var mesh))
        {
            var rng=new SeedRandom(seed);var ring=new Vector2[28]; float phase=rng.Range(0,Mathf.Tau);
            for(int i=0;i<ring.Length;i++)
            {
                float a=i*Mathf.Tau/ring.Length;
                float r=.88f+.13f*Mathf.Cos(a*3+phase)+.065f*Mathf.Sin(a*5-phase);
                ring[i]=new(Mathf.Cos(a)*r,Mathf.Sin(a)*r*.83f);
            }
            islands[seed]=mesh=new(ring);
        }
        canvas.DrawSetTransform(p);
        var outer=mesh.Ring.Select(v=>v*radius).ToArray();
        // Uneven shallows and a broad low beach surround a raised rocky interior.
        Poly(outer.Select((v,i)=>v*(1.15f+.04f*Mathf.Sin(i*1.6f))+new Vector2(0,9)).ToArray(),new Color(.13f,.53f,.54f,.27f));
        Poly(outer.Select((v,i)=>v*(1.065f+.02f*Mathf.Cos(i))+new Vector2(0,5)).ToArray(),new Color(.2f,.66f,.61f,.55f));
        Poly(Shift(outer,new(0,4)),SandShade);
        Poly(outer,Sand);
        Poly(outer.Select(v=>v*.95f-new Vector2(0,2)).ToArray(),SandLight);
        // Smaller high bank offset to the back leaves an open crescent of sand in front.
        var bank=outer.Select(v=>v*new Vector2(.7f,.64f)-new Vector2(radius*.09f,radius*.19f)).ToArray();
        Prism(bank,radius*.12f,new Color("91927a"),new Color("737665"));
        var foam=outer.Select(v=>v*1.035f+new Vector2(0,4)).ToArray();
        for(int i=0;i<foam.Length;i+=4)
            canvas.DrawPolyline([foam[i],foam[(i+1)%foam.Length],foam[(i+2)%foam.Length]],new Color(Cream,.5f),2,true);
        var rocks=new SeedRandom(seed ^ 0xa812u);
        for(int i=0;i<7;i++)
        {
            float a=2.15f+i*.53f;
            var at=new Vector2(Mathf.Cos(a)*radius*.58f,Mathf.Sin(a)*radius*.36f-radius*.12f);
            Boulder(at,radius*rocks.Range(.19f,.34f),seed+(uint)i);
        }
        for(int i=0;i<3;i++)
        {
            var at=new Vector2(-radius*.28f+i*radius*.22f,-radius*.18f);
            Poly([at+new Vector2(-14,6),at+new Vector2(-8,-6),at+new Vector2(5,-10),at+new Vector2(17,3),at+new Vector2(3,9)],new Color(i%2==0?"788153":"929661"));
        }
        // Loose shore stones break up the beach edge without extending the collision footprint.
        for(int i=0;i<3;i++)
        {
            float a=.4f+i*2.2f; var at=new Vector2(Mathf.Cos(a)*radius*.85f,Mathf.Sin(a)*radius*.68f);
            Boulder(at,radius*rocks.Range(.08f,.14f),seed+(uint)i+20);
        }
        if(harbor)
        {
            Boulder(new(radius*.36f,-radius*.18f),radius*.36f,seed ^ 72u);
            Dock(new(12,radius*.55f));
            Hut(new(-radius*.37f,-8));
            Lighthouse(new(radius*.38f,-radius*.4f),clock);
            Crate(new(-30,50));Crate(new(-8,60));
            Box(new(-13,-43),new(8,13),16,new Color("739750"),new Color("395943"));
        }
        canvas.DrawSetTransform(Vector2.Zero);
    }
    void Dock(Vector2 p)
    {
        for(int y=0;y<9;y++)
        {
            float x=y>3?18:0;Box(p+new Vector2(x-28,y*12),new(62,10),5,y%2==0?new Color("bc8b4e"):new Color("ce9e5b"),new Color("725032"));
            Line(p+new Vector2(x-22,y*12-3),p+new Vector2(x+27,y*12-3),new Color("e6ba76"),1);
            for(int side=-1;side<=1;side+=2)Ellipse(p+new Vector2(x+side*23,y*12-1),new(1.6f,1),Ink);
        }
        for(int y=0;y<3;y++)for(int side=-1;side<=1;side+=2)
        {var at=p+new Vector2(side*34+(y>0?18:0),y*43+5);Box(at,new(10,12),18,new Color("e5bf7d"),new Color("735231"));Line(at+new Vector2(3,-12),at+new Vector2(7,-12),SandShade,2);}
    }
    void Hut(Vector2 p)
    {
        var shape=new[]{p+new Vector2(-26,-12),p+new Vector2(27,-12),p+new Vector2(27,30),p+new Vector2(-26,30)};
        Prism(shape,34,Cream,Sand);
        Box(p+new Vector2(-7,12),new(17,19),0,Ink,Ink);
        Box(p+new Vector2(-22,3),new(10,11),0,Ink,Ink);
        Poly([p+new Vector2(-34,-43),p+new Vector2(23,-43),p+new Vector2(35,-10),p+new Vector2(-25,-10)],Orange);
        Poly([p+new Vector2(23,-43),p+new Vector2(35,-10),p+new Vector2(35,1),p+new Vector2(23,-31)],OrangeDark);
        Line(p+new Vector2(-34,-43),p+new Vector2(23,-43),OrangeLight,3);
        for(int i=1;i<=3;i++)Line(p+new Vector2(-34+i*3,-43+i*9),p+new Vector2(23+i*3,-43+i*9),OrangeDark,1.5f);
        for(int i=1;i<5;i++)Line(p+new Vector2(-34+i*11,-43),p+new Vector2(-25+i*12,-10),OrangeLight,1);
    }
    void Lighthouse(Vector2 p,float clock)
    {
        Vector2[] baseRing=Enumerable.Range(0,8).Select(i=>p+new Vector2(Mathf.Cos(i*Mathf.Tau/8)*21,Mathf.Sin(i*Mathf.Tau/8)*14)).ToArray();
        var top=baseRing.Select(v=>p+(v-p)*.62f-new Vector2(0,82)).ToArray();
        for(int i=0;i<8;i++){int j=(i+1)%8;Poly([baseRing[i],baseRing[j],top[j],top[i]],i<4?Sand:Cream);}
        Box(p+new Vector2(-4,-14),new(8,13),0,Ink,Ink);Box(p+new Vector2(-4,-59),new(5,10),0,Ink,Ink);
        var deck=Enumerable.Range(0,8).Select(i=>p+new Vector2(Mathf.Cos(i*Mathf.Tau/8)*23,Mathf.Sin(i*Mathf.Tau/8)*14-85)).ToArray();Prism(deck,4,Cream,RockDark);
        Box(p+new Vector2(-12,-90),new(24,12),22,new Color("ffdd85"),new Color("edb85a"));
        for(int i=0;i<6;i++){float a=i*Mathf.Tau/6;Vector2 v=p+new Vector2(Mathf.Cos(a)*14,Mathf.Sin(a)*9-93);Line(v,v-new Vector2(0,23),Ink,3);}
        var roof=Enumerable.Range(0,6).Select(i=>p+new Vector2(Mathf.Cos(i*Mathf.Tau/6)*24,Mathf.Sin(i*Mathf.Tau/6)*13-116)).ToArray();
        for(int i=0;i<6;i++)Poly([roof[i],roof[(i+1)%6],p+new Vector2(-3,-137)],i%3==0?CoralDark:Coral);
        Line(p+new Vector2(-3,-138),p+new Vector2(-3,-144),Metal,2);
    }
    void Crate(Vector2 p){Box(p,new(15,13),12,new Color("d8a35c"),new Color("8e6133"));Line(p+new Vector2(2,-10),p+new Vector2(13,-1),new Color("805728"),2);Line(p+new Vector2(13,-10),p+new Vector2(2,-1),new Color("805728"),2);}
    void Boulder(Vector2 p,float radius,uint seed)
    {
        float skew = (seed % 7 - 3f)*.035f;
        var ring = new Vector2[] { new(-.8f,.28f),new(-.9f,-.16f),new(-.42f,-.8f),new(.25f+skew,-1),new(.79f,-.32f),new(.9f,.28f),new(.28f,.63f),new(-.42f,.57f) };
        ring=ring.Select(v=>p+v*radius).ToArray();
        Poly(Shift(ring,new(3,5)),Shadow); Poly(ring,new Color("777967"));
        var peak=p+new Vector2(-.13f,-.32f)*radius;
        Poly([ring[0],ring[1],ring[2],peak,ring[7]],new Color("aaa58a"));
        Poly([ring[2],ring[3],ring[4],peak],new Color("c0b99a"));
        Poly([peak,ring[4],ring[5],ring[6]],new Color("62695e"));
    }
    public void Rocks(Vector2 p,float radius,uint seed)
    {
        canvas.DrawSetTransform(p);
        Ellipse(new(0,8),new(radius*1.25f,radius*.66f),new Color(.22f,.64f,.6f,.2f));
        for(int i=0;i<3;i++)
        {Vector2 at=new((i-1)*radius*.55f,(i==1?-.3f:.2f)*radius);float r=radius*(i==1?.78f:.49f);Boulder(at,r,seed+(uint)i);}
        Line(new(-radius*.9f,radius*.4f),new(-radius*.4f,radius*.52f),new Color(Cream,.5f),2);
        canvas.DrawSetTransform(Vector2.Zero);
    }
    public void Trim(IEnumerable<uint> active) { var keep=active.ToHashSet(); foreach(var key in islands.Keys.ToArray())if(!keep.Contains(key))islands.Remove(key); }
}
