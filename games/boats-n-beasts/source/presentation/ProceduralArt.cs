using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Original art, drawn from polygons and lit, bevelled surfaces. No imported art or textures.
public sealed class ProceduralArt(Node2D canvas)
{
    static readonly Color Cream = new("ffe4ac"), Sand = new("e2c38a"), SandLight = new("ffe9b8"), SandShade = new("b3946b"), RockDark = new("273c58");
    static readonly Color Orange = new("f87929"), OrangeLight = new("ffab45"), OrangeDark = new("b84018"), Coral = new("f75f42"), CoralLight = new("ff986a"), CoralDark = new("a6322b"), Ink = new("102944"), Metal = new("374454");
    static readonly Color Shadow = new(.012f, .10f, .26f, .55f);
    readonly Dictionary<uint, IslandMesh> islands = new();
    sealed record IslandMesh(Vector2[] Ring, Vector2[] Inner, float[] Heights);
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
        Prism(hull, 3, OrangeDark, Ink);
        Prism(Shift(Hull(width-3, 133),new(0,-4)), 7, Cream, SandShade, SandLight);
        Poly(Shift(Hull(width-16, 114), new(0,-11)), Ink);
        Poly(Shift(Hull(width-20, 110), new(0,-12)), Sand);
        for(int i=0;i<5;i++) Line(new(-width*.32f, -31+i*15),new(width*.32f,-31+i*15),new Color("c9a774"),1);
        // Gunwales, tie-off cleats and orange hull stripe.
        Line(new(-width*.43f,-22),new(-width*.43f,24),SandLight,3);
        Line(new(width*.43f,-22),new(width*.43f,24),Cream,3);
        for(int side=-1;side<=1;side+=2)for(int y=-29;y<=34;y+=63)
        { Ellipse(new(side*width*.4f,y),new(4,7),Ink);Line(new(side*width*.4f-4,y),new(side*width*.4f+4,y),Metal,2); }
        // Raised cabin, dark panoramic windows, bevelled orange roof.
        float cabinW=tug?48:35;
        Box(new(-cabinW/2,-16),new(cabinW,39),15,tug?new Color("49b8a7"):Orange,tug?new Color("247374"):OrangeDark);
        Poly([new(-cabinW/2+3,10),new(-cabinW/2+3,20),new(cabinW/2-3,20),new(cabinW/2-3,10)],Ink);
        Line(new(-cabinW/2+5,12),new(cabinW/2-5,12),new Color("61939e"),2);
        Line(new(0,10),new(0,21),Orange,3);
        Poly([new(-cabinW/2,-31),new(cabinW/2,-31),new(cabinW/2-4,-11),new(-cabinW/2+4,-11)],tug?new Color("9ae8cb"):OrangeLight);
        Poly([new(-cabinW/2+4,-29),new(cabinW/2-4,-29),new(cabinW/2-6,-13),new(-cabinW/2+6,-13)],tug?new Color("49b8a7"):Orange);
        Line(new(-cabinW/2,-31),new(cabinW/2,-31),new Color("ffcc72"),2);
        Box(new(-8,-27),new(16,10),2,OrangeLight,OrangeDark);
        if(tug)
        {
            for(int side=-1;side<=1;side+=2){Box(new(side*25-5,28),new(10,16),17,Metal,Ink);Ellipse(new(side*25,11),new(5,4),Ink);}
        }
        else { Line(new(-15,22),new(-16,43),Metal,2);Ellipse(new(-16,43),new(5,3),Cream); }
        Gun(new(0,-48),aimAngle,weapons != null && weapons[0] >= 3);
        Gun(new(0,42),aimAngle,false);
        if (muzzle)
        {
            int count=weapons!=null && weapons[0]>=3?2:1;
            var dir=Vector2.FromAngle(aimAngle-Mathf.Pi/2);
            for(int barrel=0;barrel<count;barrel++)
            {
                var at=new Vector2(0,-48)+dir*25+dir.Orthogonal()*(count==2?(barrel==0?-9:9):0);
                for(int i=0;i<5;i++){float a=i*Mathf.Tau/5;Spike(at,at+Vector2.FromAngle(a)*11,3,Cream);}
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
        Color top = flash ? Cream : new Color("b48bde"), dark = new("514b89");
        var wing = new Vector2[] { new(-60, 10 + flap), new(-24,-18), new(0,-32), new(24,-18), new(60,10+flap), new(18,22), new(0,10), new(-18,22) };
        Poly(Shift(wing, new(5,9)), Shadow);
        for (int i=0;i<wing.Length;i++) Poly([wing[i],wing[(i+1)%wing.Length],new(0,-8)],i%3==0?dark:top.Darkened(i*.025f));
        Spike(new(0,8),new(8+MathF.Sin(clock*3)*8,65),6,dark);
        Line(new(-45,8+flap),new(-8,-12),top.Lightened(.3f),2);
        Line(new(45,8+flap),new(8,-12),top.Lightened(.3f),2);
        Eye(new(-9,-13),5); Eye(new(9,-13),5);
    }
    void Shell(Vector2 p,Vector2 radius,Color top,Color dark,int sides,uint seed)
    {
        var rng=new SeedRandom(seed);var ring=new Vector2[sides];var inner=new Vector2[sides];
        for(int i=0;i<sides;i++)
        {float a=i*Mathf.Tau/sides;ring[i]=p+new Vector2(Mathf.Cos(a)*radius.X,Mathf.Sin(a)*radius.Y);inner[i]=p+new Vector2(Mathf.Cos(a)*radius.X*.59f,Mathf.Sin(a)*radius.Y*.56f-radius.Y*.23f);}
        Poly(Shift(ring,new(4,7)),Shadow);
        for(int i=0;i<sides;i++)
        {
            int j=(i+1)%sides;float shade=.72f+(.5f-ring[i].X/(radius.X*3)-ring[i].Y/(radius.Y*4))*.35f;
            Poly([ring[i],ring[j],inner[j]],dark.Lerp(top,Mathf.Clamp(shade,0,1)));
            Poly([ring[i],inner[j],inner[i]],top.Darkened(rng.Range(.03f,.17f)));
            Poly([inner[i],inner[j],p+new Vector2(-radius.X*.15f,-radius.Y*.27f)],top.Lightened(rng.Range(0,.13f)));
        }
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
        for(int i=0;i<9;i++)
        {float a=Mathf.Pi+i*Mathf.Pi/8;var root=new Vector2(Mathf.Cos(a)*31*s,Mathf.Sin(a)*24*s);Spike(root,root+new Vector2(Mathf.Cos(a)*12,Mathf.Sin(a)*15)*s,4*s,boss?Cream:Coral);}
        Shell(new(0,0),new(36*s,29*s),flash?Cream:Coral,CoralDark,13,72);
        if(boss)
        {
            Shell(new(0,-4*s),new(26*s,19*s),Metal,Ink,7,128);
            for(int i=-1;i<=1;i++)Spike(new(i*15*s,-13*s),new(i*22*s,-(i==0?54:41)*s),7*s,Cream);
            for(int side=-1;side<=1;side+=2)Spike(new(side*24*s,3*s),new(side*39*s,-5*s),5*s,Cream);
        }
        else
        {
            Spike(new(-17,-8),new(-20,-18),3,CoralLight);Spike(new(5,-10),new(3,-21),3,CoralLight);Spike(new(21,0),new(27,-8),3,CoralLight);
        }
        Eye(new(-13*s,17*s),7*s,boss);Eye(new(13*s,17*s),7*s,boss);
        Poly([new(-7*s,28*s),new(7*s,28*s),new(0,32*s)],Ink);
        for(int side=-1;side<=1;side+=2)
        {
            float sway=MathF.Sin(clock*3+side)*4;
            Leg(new(side*27*s,19*s),new(side*42*s,34*s),new(side*35*s,(46+sway)*s),7*s);
            var at=new Vector2(side*34*s,(48+sway)*s);
            Poly([at+new Vector2(-13*s,-6*s),at+new Vector2(-15*s,8*s),at+new Vector2(-5*s,18*s),at+new Vector2(6*s,17*s),at+new Vector2(-2*s,9*s),at+new Vector2(-4*s,-2*s)],Coral);
            Poly([at+new Vector2(8*s,-7*s),at+new Vector2(15*s,3*s),at+new Vector2(10*s,15*s),at+new Vector2(6*s,6*s),at+new Vector2(0,-2*s)],CoralLight);
            if(boss){Spike(at+new Vector2(-3*s,14*s),at+new Vector2(7*s,19*s),4*s,Cream);}
        }
    }
    void Puffer(float clock,bool flash)
    {
        for(int i=0;i<13;i++){float a=i*Mathf.Tau/13;var root=new Vector2(Mathf.Cos(a)*32,Mathf.Sin(a)*31);Spike(root,root+new Vector2(Mathf.Cos(a),Mathf.Sin(a))*16,5,Coral);}
        Shell(new(0,0),new(37,35),flash?Cream:Coral,CoralDark,14,391);
        for(int i=0;i<5;i++){float a=i*2.7f;var p=new Vector2(Mathf.Cos(a)*23,Mathf.Sin(a)*19);Spike(p,p+new Vector2(-3,-10),4,CoralLight);}
        Eye(new(-2,-1),13,true);Ellipse(new(28,15),new(10,9),CoralDark);Ellipse(new(29,14),new(7,7),Ink);Line(new(24,9),new(30,7),CoralLight,3);
        Poly([new(-30,7),new(-49,13+MathF.Sin(clock*8)*3),new(-31,22)],CoralDark);
    }
    void Serpent(float clock,float facing,bool flash)
    {
        var path=new Vector2[13];
        for(int i=0;i<path.Length;i++){float t=i/12f;path[i]=new((t-.5f)*130,MathF.Sin(t*6+clock*3)*14+(t-.5f)*20);}
        // Head is on the left; body visibly undulates even while its collision center follows the chase path.
        for(int i=12;i>=1;i--)
        {
            float r=4+(1-i/13f)*16;var a=path[i];var b=path[i-1];var n=(b-a).Normalized().Orthogonal();
            Poly([a+n*r+new Vector2(4,8),b+n*(r+1)+new Vector2(4,8),b-n*(r+1)+new Vector2(4,8),a-n*r+new Vector2(4,8)],Shadow);
            Poly([a+n*r,b+n*(r+1),b-n*(r+1),a-n*r],flash?Cream:CoralDark);
            Poly([a+n*r,b+n*(r+1),b,a],flash?Cream:Coral);
            Line(a+n*r,b+n*(r+1),CoralLight,2);
            if(i%2==0)Spike(a-n*r,a-n*(r+11)+new Vector2(8,0),5,Coral);
        }
        var head=path[0];
        Poly([head+new Vector2(-25,1),head+new Vector2(-8,-19),head+new Vector2(19,-13),head+new Vector2(19,15),head+new Vector2(-8,21)],flash?Cream:Coral);
        Poly([head+new Vector2(-25,1),head+new Vector2(-5,0),head+new Vector2(7,10),head+new Vector2(-18,12)],Ink);
        for(int i=0;i<3;i++)Spike(head+new Vector2(-16+i*8,2),head+new Vector2(-13+i*8,9),2,Cream);
        Eye(head+new Vector2(-4,-9),6,true);Spike(head+new Vector2(13,-12),head+new Vector2(23,-30),5,CoralLight);
    }
    public void Island(Vector2 p,float radius,uint seed,bool harbor,float clock)
    {
        if(!islands.TryGetValue(seed,out var mesh))
        {
            var rng=new SeedRandom(seed);var ring=new Vector2[14];var inner=new Vector2[14];var heights=new float[14];
            for(int i=0;i<14;i++){float a=i*Mathf.Tau/14;float r=rng.Range(.85f,1.12f);ring[i]=new(Mathf.Cos(a)*r,Mathf.Sin(a)*r*.72f);inner[i]=new(Mathf.Cos(a)*.55f,Mathf.Sin(a)*.4f);heights[i]=rng.Range(.05f,.28f);}
            islands[seed]=mesh=new(ring,inner,heights);
        }
        canvas.DrawSetTransform(p);
        var outer=mesh.Ring.Select(v=>v*radius).ToArray();var innerPoints=mesh.Inner.Select((v,i)=>v*radius-new Vector2(0,mesh.Heights[i]*radius)).ToArray();
        Poly(outer.Select(v=>v*1.16f+new Vector2(0,7)).ToArray(),new Color(.12f,.62f,.68f,.16f));
        Poly(Shift(outer,new(10,17)),Shadow);
        for(int i=0;i<14;i++)
        {
            int j=(i+1)%14;var baseI=outer[i];var baseJ=outer[j];var edgeI=baseI-new Vector2(0,10);var edgeJ=baseJ-new Vector2(0,10);
            Poly([baseI,baseJ,edgeJ,edgeI],i<7?RockDark:SandShade);
            Poly([edgeI,edgeJ,innerPoints[j]],i%3==0?SandLight:i%3==1?Sand:SandShade);
            Poly([edgeI,innerPoints[j],innerPoints[i]],i%4==0?SandShade:Sand);
            Poly([innerPoints[i],innerPoints[j],new Vector2(-10,-radius*.15f)],i%3==0?SandLight:Sand.Lerp(SandLight,.35f));
            float wave=Mathf.Sin(clock*1.6f+i*.8f);var a=baseI*1.05f+new Vector2(0,6);var b=baseI.Lerp(baseJ,.63f)*1.05f+new Vector2(0,6);
            Line(a,b,new Color(Cream,.65f+wave*.2f),2.7f);if(i%2==0)Ellipse(a+new Vector2(5,5),new(2,1),Cream);
        }
        if(harbor)
        {
            Dock(new(12,radius*.55f));
            Hut(new(-radius*.37f,-8));
            Lighthouse(new(radius*.38f,-radius*.25f),clock);
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
        for(int i=0;i<6;i++)Poly([roof[i],roof[(i+1)%6],p+new Vector2(-3,-137)],i%3==0?Metal:Ink);
        Line(p+new Vector2(-3,-138),p+new Vector2(-3,-144),Metal,2);
    }
    void Crate(Vector2 p){Box(p,new(15,13),12,new Color("d8a35c"),new Color("8e6133"));Line(p+new Vector2(2,-10),p+new Vector2(13,-1),new Color("805728"),2);Line(p+new Vector2(13,-10),p+new Vector2(2,-1),new Color("805728"),2);}
    public void Rocks(Vector2 p,float radius,uint seed)
    {
        canvas.DrawSetTransform(p);
        for(int i=0;i<3;i++)
        {Vector2 at=new((i-1)*radius*.55f,(i==1?-.3f:.2f)*radius);float r=radius*(i==1?.78f:.49f);Shell(at,new(r,r*.77f),Sand,RockDark,5,seed+(uint)i);}
        canvas.DrawSetTransform(Vector2.Zero);
    }
    public void Trim(IEnumerable<uint> active) { var keep=active.ToHashSet(); foreach(var key in islands.Keys.ToArray())if(!keep.Contains(key))islands.Remove(key); }
}
