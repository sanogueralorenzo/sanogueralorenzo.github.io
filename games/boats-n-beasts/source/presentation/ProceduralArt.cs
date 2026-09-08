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
        canvas.DrawPolyline([new(-width*.57f,30),new(-width*.6f,-15),new(-width*.4f,-52),new(0,-83)],new Color(.65f,.88f,.82f,.35f),2,true);
        canvas.DrawPolyline([new(width*.57f,30),new(width*.6f,-15),new(width*.4f,-52),new(0,-83)],new Color(.65f,.88f,.82f,.25f),2,true);
        var hull = Hull(width, 139);
        Poly(Shift(hull, new(7, 9)), Shadow);
        Prism(hull, 7, new Color("3c5260"), Ink);
        Prism(Shift(Hull(width-3, 133),new(0,-4)), 10, Cream, new Color("99794f"), SandLight);
        Poly(Shift(Hull(width-16, 114), new(0,-11)), Ink);
        Poly(Shift(Hull(width-20, 110), new(0,-12)), new Color("bc915d"));
        for(int i=0;i<3;i++) Line(new(-width*.32f, -24+i*24),new(width*.32f,-24+i*24),new Color("c9a774"),1);
        // Gunwales, tie-off cleats and orange hull stripe.
        Line(new(-width*.43f,-22),new(-width*.43f,24),SandLight,3);
        Line(new(width*.43f,-22),new(width*.43f,24),Cream,3);
        for(int side=-1;side<=1;side+=2)for(int y=-29;y<=34;y+=63)
        { Ellipse(new(side*width*.4f,y),new(4,7),Ink);Line(new(side*width*.4f-4,y),new(side*width*.4f+4,y),Metal,2); }
        // Cabin height and lighting stay in screen space while the deck turns.
        float cabinW=tug?48:35;
        bool mage = kind == BoatKind.Mage;
        var cabinUp=Vector2.FromAngle(-Mathf.Pi/2-angle)*22;
        Vector2[] cabin=[new(-cabinW/2,-10),new(cabinW/2,-10),new(cabinW/2,26),new(-cabinW/2,26)];
        var cabinShadow=Vector2.FromAngle(.7f-angle)*17;
        Poly(Shift(cabin,cabinShadow),new Color(.12f,.12f,.1f,.22f));
        for(int face=0;face<4;face++)
        {
            var a=cabin[face]; var b=cabin[(face+1)%4];
            var normal=(b-a).Rotated(angle).Orthogonal().Normalized();
            if(normal.Y<0)continue;
            var wall=normal.X<0?new Color("d9bb87"):new Color("a28361");
            Poly([a,b,b+cabinUp,a+cabinUp],wall);
            var left=a.Lerp(b,.16f); var right=a.Lerp(b,.84f);
            Poly([left+cabinUp*.25f,right+cabinUp*.25f,right+cabinUp*.8f,left+cabinUp*.8f],Ink);
            Line(left+cabinUp*.73f,right+cabinUp*.73f,new Color("76b0b7"),2);
            Line(a.Lerp(b,.5f)+cabinUp*.2f,a.Lerp(b,.5f)+cabinUp*.86f,Cream,2);
        }
        var roof=cabin.Select(v=>v*new Vector2(1.12f,1.03f)+cabinUp).ToArray();
        Poly(roof,Cream);
        var roofCenter=new Vector2(0,8)+cabinUp;
        var roofInset=roof.Select(v=>roofCenter+(v-roofCenter)*.77f).ToArray();
        Poly(roofInset,mage?new Color("8e70bb"):new Color("d8b77d"));
        Poly([roofInset[0],roofInset[1],roofCenter],mage?new Color("baa0e3"):SandLight);
        Line(roof[0],roof[1],SandLight,2);
        var hatch=roofCenter-new Vector2(0,3);
        Poly([hatch+new Vector2(-6,-7),hatch+new Vector2(6,-7),hatch+new Vector2(6,4),hatch+new Vector2(-6,4)],Cream);
        if(tug)
        {
            Ellipse(new(0,30),new(18,13),new Color("1d5b63"));
            Ellipse(new(0,28),new(12,8),new Color("6bd4bd"));
            Ellipse(new(0,27),new(6,4),Cream);
            for(int side=-1;side<=1;side+=2){Box(new(side*25-5,28),new(10,16),17,Metal,Ink);Ellipse(new(side*25,11),new(5,4),Ink);}
        }
        else { Line(new(-15,22),new(-16,43),Metal,2);Ellipse(new(-16,43),new(5,3),Cream); }
        if (weapons != null && weapons[0] > 0) Gun(new(0,-48),aimAngle,weapons[0]);
        if (muzzle && weapons != null && weapons[0] > 0)
        {
            int count=weapons[0];
            var dir=Vector2.FromAngle(aimAngle-Mathf.Pi/2);
            for(int barrel=0;barrel<count;barrel++)
            {
                var at=new Vector2(0,-48)+dir*25+dir.Orthogonal()*((barrel-(count-1)/2f)*9);
                for(int i=0;i<3;i++){float a=i*Mathf.Tau/5;Spike(at,at+Vector2.FromAngle(a)*11,3,Cream);}
            }
        }
        if(weapons!=null && weapons[5]>0)
        {
            var crystal = new Vector2(0,-48);
            float radius = 14 + weapons[5]*2;
            // Keep crystal height vertical on screen while the hull turns beneath it.
            var up=Vector2.FromAngle(-Mathf.Pi/2-angle);
            var right=Vector2.FromAngle(-angle);
            var tip=crystal+up*43;
            var shoulder=crystal+up*19;
            Ellipse(crystal+up*20,new(radius*1.65f,28),new Color(.65f,.4f,1,.1f));
            Ellipse(crystal+new Vector2(0,5),new(radius+7,8),Ink);
            Poly([tip,shoulder+right*radius,crystal,shoulder-right*radius],new Color("b6a0f4"));
            Poly([tip,crystal,shoulder-right*radius],new Color("7953b4"));
            Poly([tip,shoulder+right*radius,shoulder+right*3],new Color("dec8ff"));
            for(int orb=0;orb<weapons[5];orb++)
            {
                float a=clock*.9f+orb*Mathf.Tau/weapons[5];
                Ellipse(crystal+new Vector2(Mathf.Cos(a)*23,Mathf.Sin(a)*10),new(3,3),new Color("dfceff"));
            }
        }
        if(weapons!=null && weapons[1]>0){Line(new(width*.34f,5),new(width*.34f,-21),Metal,5);Poly([new(width*.34f,-29),new(width*.34f-5,-18),new(width*.34f+5,-18)],Cream);}
        if(weapons!=null && weapons[2]>0){Ellipse(new(0,39),new(11,9),Ink);Ellipse(new(0,37),new(8,7),Metal);Line(new(-12,37),new(12,37),Cream,2);}
        if(weapons!=null && weapons[3]>0){Box(new(width*.24f-5,27),new(10,12),5,Metal,Ink);for(int i=0;i<weapons[3]+2;i++)Ellipse(new(width*.24f,23-i*3),new(6,2),new Color("69e1d3"));}
        if(flash)canvas.DrawPolyline(Shift(hull,new(0,-5)).Append(hull[0]+new Vector2(0,-5)).ToArray(),new Color("fff9e4"),3,true);
        canvas.DrawSetTransform(Vector2.Zero);
    }
    void Gun(Vector2 p, float angle, int count)
    {
        Ellipse(p+new Vector2(2,4),new(8+count*4,10),Ink); Ellipse(p,new(7+count*4,9),Cream); Ellipse(p+new Vector2(0,-3),new(4+count*4,7),Metal);
        var d=Vector2.FromAngle(angle-Mathf.Pi/2); var side=d.Orthogonal();
        for(int i=0;i<count;i++)
        {
            var at=p+side*((i-(count-1)/2f)*9);
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
        Shell(new(0,-5),new(18,26),flash?Cream:Teal,TealDark,12,82);
        Spike(new(0,8),new(8+MathF.Sin(clock*3)*8,65),4,TealDark);
        Eye(new(-9,-13),4); Eye(new(9,-13),4);
    }
    void Shell(Vector2 p,Vector2 radius,Color top,Color dark,int sides,uint seed)
    {
        var ring = Enumerable.Range(0, sides).Select(i => p + new Vector2(Mathf.Cos(i*Mathf.Tau/sides)*radius.X, Mathf.Sin(i*Mathf.Tau/sides)*radius.Y)).ToArray();
        Poly(Shift(ring,new(4,8)),Shadow);
        Poly(ring,dark);
        var shoulder = ring.Select(v=>p+(v-p)*new Vector2(.86f,.86f)-new Vector2(0,radius.Y*.04f)).ToArray();
        var crown = ring.Select(v=>p+(v-p)*new Vector2(.55f,.55f)-new Vector2(radius.X*.04f,radius.Y*.17f)).ToArray();
        for(int i=0;i<sides;i++)
        {
            int next=(i+1)%sides;
            float light=Mathf.Cos((i+.5f)*Mathf.Tau/sides+2.1f);
            Color face=light>0?top.Lightened(light*.17f):top.Darkened(-light*.2f);
            Poly([ring[i],ring[next],shoulder[next],shoulder[i]],dark.Lerp(face,.6f));
            Poly([shoulder[i],shoulder[next],crown[next],crown[i]],face);
        }
        Poly(crown,top.Lightened(.13f));
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
        Shell(new(0,0),new(36*s,29*s),flash?Cream:Coral,CoralDark,16,72);
        if(boss)
        {
            Shell(new(0,-4*s),new(26*s,19*s),Metal,Ink,7,128);
            for(int i=-1;i<=1;i++)Spike(new(i*15*s,-13*s),new(i*22*s,-(i==0?54:41)*s),7*s,Cream);
            for(int side=-1;side<=1;side+=2)Spike(new(side*24*s,3*s),new(side*39*s,-5*s),5*s,Cream);
        }
        Eye(new(-13*s,17*s),8*s,boss);Eye(new(13*s,17*s),8*s,boss);
        Poly([new(-7*s,28*s),new(7*s,28*s),new(0,32*s)],Ink);
        for(int side=-1;side<=1;side+=2)
        {
            float sway=MathF.Sin(clock*3+side)*4;
            Leg(new(side*27*s,19*s),new(side*42*s,34*s),new(side*35*s,(46+sway)*s),7*s);
            var at=new Vector2(side*34*s,(48+sway)*s);
            Ellipse(at,new(14*s,16*s),CoralDark);
            Ellipse(at+new Vector2(-2*s,-2*s),new(12*s,14*s),flash?Cream:Coral);
            Ellipse(at+new Vector2(-5*s,-6*s),new(6*s,7*s),flash?Cream:CoralLight);
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
            float r=3+(1-t)*21;
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
    Vector2[] IslandRing(uint seed)
    {
        if (!islands.TryGetValue(seed, out var mesh))
        {
            var rng=new SeedRandom(seed); var ring=new Vector2[40]; float phase=rng.Range(0,Mathf.Tau);
            for(int i=0;i<ring.Length;i++)
            {
                float a=i*Mathf.Tau/ring.Length;
                float r=.9f+.1f*Mathf.Cos(a*3+phase)+.04f*Mathf.Sin(a*5-phase);
                ring[i]=new(Mathf.Cos(a)*r,Mathf.Sin(a)*r*.83f);
            }
            islands[seed]=mesh=new(ring);
        }
        return mesh.Ring;
    }
    public void Surf(Vector2 p, float radius, uint seed, float clock)
    {
        var ring=IslandRing(seed);
        for (int wave=0;wave<2;wave++)
        {
            float phase=(clock*.14f+wave*.5f+seed%11*.08f)%1;
            float alpha=Mathf.Sin(phase*Mathf.Pi)*.7f;
            for(int start=0;start<ring.Length;start+=10)
            {
                var points=new Vector2[7];
                for(int i=0;i<points.Length;i++) points[i]=p+ring[(start+i)%ring.Length]*radius*(1.02f+phase*.13f)+new Vector2(0,4);
                canvas.DrawPolyline(points,new Color(new Color("edf9dc"),alpha),2.6f,true);
                for(int foam=1;foam<points.Length;foam+=3)
                    canvas.DrawCircle(points[foam]+new Vector2(Mathf.Sin(foam+seed%7)*4,3),1.3f,new Color(Cream,alpha*.6f));
            }
        }
    }
    public void Island(Vector2 p,float radius,uint seed,bool harbor,float clock)
    {
        var ring=IslandRing(seed);
        canvas.DrawSetTransform(p);
        var outer=ring.Select(v=>v*radius).ToArray();
        float shoalPhase=(seed%997)/997f*Mathf.Tau;
        Poly(Shift(outer,new(3,8)),new Color("9b895f"));
        Poly(outer,Sand);
        var beach=outer.Select(v=>v*.975f-new Vector2(0,2)).ToArray();
        var inland=outer.Select((v,i)=>v*(.79f+.035f*Mathf.Sin(i*.8f+shoalPhase))-new Vector2(0,5)).ToArray();
        Poly(inland,new Color("eed29b"));
        for(int i=0;i<outer.Length;i++)
        {
            int next=(i+1)%outer.Length;
            var rim=SandLight;
            var center=new Color("eed29b");
            canvas.DrawPolygon([beach[i],beach[next],inland[next]],[rim,rim,center]);
            canvas.DrawPolygon([beach[i],inland[next],inland[i]],[rim,center,center]);
        }
        var bank=outer.Select(v=>v*new Vector2(.60f,.55f)-new Vector2(radius*.03f,radius*.16f)).ToArray();
        var bankCenter=new Vector2(-radius*.03f,-radius*.2f);
        for(int i=0;i<bank.Length;i++)
        {
            int next=(i+1)%bank.Length;
            var edge=bank[i]*(1+.09f*Mathf.Sin(i*1.9f+shoalPhase));
            var nextEdge=bank[next]*(1+.09f*Mathf.Sin(next*1.9f+shoalPhase));
            canvas.DrawPolygon([bankCenter,edge,nextEdge],[new Color("93a174"),new Color(.58f,.63f,.43f,.12f),new Color(.58f,.63f,.43f,.12f)]);
        }
        var sandGrain=new SeedRandom(seed ^ 0x17f3u);
        for(int grain=0;grain<30;grain++)
        {
            float a=sandGrain.Range(0,Mathf.Tau);
            int edge=(int)(a/Mathf.Tau*outer.Length)%outer.Length;
            var point=outer[edge]*sandGrain.Range(.73f,.9f);
            Ellipse(point,new(sandGrain.Range(.8f,1.8f),.8f),new Color(SandShade,.2f));
        }
        var rocks=new SeedRandom(seed ^ 0xa812u);
        // Subordinate rocks leave room for the landmark and a broad walkable-looking beach.
        for(int i=0;i<2;i++)
        {
            var at=new Vector2((i==0?-.42f:.4f)*radius,-radius*.1f);
            Boulder(at,radius*rocks.Range(.15f,.23f),seed+(uint)i);
        }
        for(int i=0;i<5;i++)
        {
            float a=i*2.4f;
            var at=new Vector2(Mathf.Cos(a)*radius*.4f,Mathf.Sin(a)*radius*.2f-radius*.22f);
            Shell(at,new(radius*.1f,radius*.07f),new Color(i%2==0?"76945d":"587d55"),new Color("4c6d4b"),7,seed+(uint)i);
        }
        // Loose shore stones break up the beach edge without extending the collision footprint.
        for(int i=0;i<3;i++)
        {
            float a=.4f+i*2.2f; var at=new Vector2(Mathf.Cos(a)*radius*.85f,Mathf.Sin(a)*radius*.68f);
            Boulder(at,radius*rocks.Range(.08f,.14f),seed+(uint)i+20);
        }
        if (!harbor)
        {
            // Each island has one legible landmark: palms, a tall rock, or a broken mast.
            switch (seed % 3)
            {
                case 0:
                    for (int tree = 0; tree < 3; tree++)
                    {
                        var root = new Vector2((tree - 1) * radius * .27f, -radius * .15f + tree * 7);
                        Palm(root,radius*(.52f+tree*.035f),tree*.7f);
                    }
                    break;
                case 1:
                    RockSpire(new(0,-radius*.09f),radius,seed);
                    Boulder(new(-radius*.3f,radius*.08f),radius*.24f,seed);
                    Boulder(new(radius*.29f,radius*.07f),radius*.18f,seed+5);
                    for(int shrub=0;shrub<4;shrub++)
                    {
                        var at=new Vector2((shrub-1.5f)*radius*.18f,radius*(.08f+.035f*(shrub%2)));
                        Shell(at,new(radius*.095f,radius*.075f),new Color(shrub%2==0?"77934d":"5e7c45"),new Color("3d5840"),7,seed+(uint)shrub);
                    }
                    break;
                default:
                    var mast = new Vector2(radius*.12f,-radius*.17f);
                    Line(mast+new Vector2(-38,29),mast+new Vector2(37,29),new Color("825b3c"),12);
                    Line(mast+new Vector2(0,30),mast+new Vector2(-9,-65),new Color("72543c"),7);
                    Poly([mast+new Vector2(-8,-59),mast+new Vector2(36,-24),mast+new Vector2(9,-29),mast+new Vector2(16,-8),mast+new Vector2(-5,-15)],Cream);
                    break;
            }
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
    void RockSpire(Vector2 p,float radius,uint seed)
    {
        // An irregular three-dimensional mesh supplies consistent face lighting and ledges.
        var rng=new SeedRandom(seed^0x8e52u);
        const int sides=8;
        float[] widths=[.37f,.31f,.23f,.22f,.13f,.105f];
        float[] heights=[0,.26f,.32f,.72f,.79f,1.06f];
        var rings=new Vector3[widths.Length][];
        for(int tier=0;tier<rings.Length;tier++)
        {
            rings[tier]=new Vector3[sides];
            for(int i=0;i<sides;i++)
            {
                float angle=i*Mathf.Tau/sides;
                float width=widths[tier]*rng.Range(.87f,1.13f)*radius;
                rings[tier][i]=new Vector3(Mathf.Cos(angle)*width-tier*radius*.009f,
                    Mathf.Sin(angle)*width*.72f,heights[tier]*radius+(tier==0?0:rng.Range(-.024f,.024f)*radius));
            }
        }
        Vector2 Project(Vector3 v)=>p+new Vector2(v.X,v.Y-v.Z);
        // The same upper-left sun casts a broad, soft shadow along the beach.
        var center=p+new Vector2(radius*.25f,radius*.13f);
        for(int i=0;i<16;i++)
        {
            float a=i*Mathf.Tau/16,b=(i+1)*Mathf.Tau/16;
            var edge=center+new Vector2(Mathf.Cos(a)*radius*.63f,Mathf.Sin(a)*radius*.27f);
            var next=center+new Vector2(Mathf.Cos(b)*radius*.63f,Mathf.Sin(b)*radius*.27f);
            canvas.DrawPolygon([center,edge,next],[new Color(.12f,.19f,.16f,.34f),new Color(.12f,.19f,.16f,0),new Color(.12f,.19f,.16f,0)]);
        }
        var faces=new List<(Vector3 A,Vector3 B,Vector3 C)>();
        for(int tier=0;tier<rings.Length-1;tier++)for(int i=0;i<sides;i++)
        {
            int next=(i+1)%sides;
            faces.Add((rings[tier][i],rings[tier][next],rings[tier+1][next]));
            faces.Add((rings[tier][i],rings[tier+1][next],rings[tier+1][i]));
        }
        var summit=rings[^1].Aggregate(Vector3.Zero,(sum,v)=>sum+v)/sides;
        for(int i=0;i<sides;i++)faces.Add((summit,rings[^1][i],rings[^1][(i+1)%sides]));
        var light=new Vector3(-.65f,.3f,.8f).Normalized();
        foreach(var face in faces.OrderBy(f=>(f.A.Y+f.B.Y+f.C.Y+f.A.Z+f.B.Z+f.C.Z)/3))
        {
            var normal=(face.B-face.A).Cross(face.C-face.A).Normalized();
            if(normal.Dot(new Vector3(0,1,1))<=0)continue;
            float illumination=Mathf.Clamp(normal.Dot(light),0,1);
            var color=new Color("465761").Lerp(new Color("b7b49b"),illumination);
            if(normal.Z>.65f)color=color.Lerp(new Color("ddd0a9"),.38f);
            Poly([Project(face.A),Project(face.B),Project(face.C)],color);
        }
    }
    void Palm(Vector2 root,float height,float phase)
    {
        var bend=new Vector2(10+Mathf.Sin(phase)*7,-height*.55f);
        var crown=root+new Vector2(12+Mathf.Sin(phase)*12,-height);
        var shade=new Color(.16f,.22f,.14f,.19f);
        var shadowTip=root+new Vector2(height*.55f,height*.23f);
        Line(root,shadowTip,shade,8);
        Ellipse(shadowTip,new(height*.38f,height*.14f),shade);
        Poly([root+new Vector2(-5,0),root+bend-new Vector2(3,0),crown-new Vector2(2,0),crown+new Vector2(3,0),root+bend+new Vector2(5,0),root+new Vector2(5,0)],new Color("705438"));
        canvas.DrawPolyline([root-new Vector2(2,0),root+bend,crown],new Color("bc9d63"),2.5f,true);
        for(int leaf=0;leaf<7;leaf++)
        {
            float a=leaf*Mathf.Tau/7+phase*.3f;
            var d=Vector2.FromAngle(a);
            var tip=crown+d*new Vector2(height*.56f,height*.3f)+new Vector2(0,height*.12f);
            var ridge=crown.Lerp(tip,.46f)-new Vector2(0,height*.1f);
            var side=d.Orthogonal()*height*.11f;
            var lit=new Color(leaf%3==0?"a1b85e":"74964d");
            var dark=new Color(leaf%3==0?"658544":"426846");
            Poly([crown,ridge+side,ridge],lit);
            Poly([ridge,ridge+side,tip],lit);
            Poly([crown,ridge,ridge-side],dark);
            Poly([ridge,tip,ridge-side],dark);
        }
        Ellipse(crown+new Vector2(2,3),new(4,3),new Color("b59b57"));
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
        // A pitched roof and a visible side wall give the harbor a small cottage silhouette.
        Vector2 P(float x,float y)=>p+new Vector2(x,y);
        Poly([P(-38,7),P(25,7),P(48,32),P(3,43),P(-23,28)],new Color(.12f,.19f,.16f,.22f));
        Poly([P(-28,-8),P(-41,-26),P(-41,7),P(-28,25)],new Color("ae9770"));
        Poly([P(-28,-8),P(28,-8),P(28,25),P(-28,25)],new Color("e2cb98"));
        Poly([P(-28,-8),P(0,-34),P(28,-8)],new Color("f3dba9"));
        Poly([P(-31,-7),P(-44,-25),P(-14,-53),P(0,-35)],new Color("b9744f"));
        Poly([P(0,-35),P(-14,-53),P(17,-25),P(31,-7)],new Color("8c5140"));
        Line(P(-14,-53),P(0,-35),new Color("d69868"),3);
        Line(P(-31,-7),P(0,-35),new Color("d79a69"),3);
        Line(P(0,-35),P(31,-7),new Color("643d31"),3);
        Poly([P(-30,-7),P(0,-31),P(30,-7),P(28,-3),P(0,-27),P(-28,-3)],new Color("76573e"));
        Poly([P(-8,4),P(7,4),P(7,25),P(-8,25)],new Color("654e39"));
        Line(P(-5,7),P(-5,23),new Color("997248"),2);
        Ellipse(P(3,15),new(1.2f,1.2f),SandLight);
        for(int side=-1;side<=1;side+=2)
        {
            float x=side*18;
            Poly([P(x-6,2),P(x+6,2),P(x+6,13),P(x-6,13)],new Color("6e624a"));
            Poly([P(x-4,3),P(x+4,3),P(x+4,10),P(x-4,10)],new Color("37636a"));
            Line(P(x-4,4),P(x+3,4),new Color("91b2aa"),1.5f);
            Line(P(x-7,14),P(x+7,14),SandLight,2);
        }
        Poly([P(-12,25),P(12,25),P(16,30),P(-10,30)],new Color("b5aa8a"));
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
