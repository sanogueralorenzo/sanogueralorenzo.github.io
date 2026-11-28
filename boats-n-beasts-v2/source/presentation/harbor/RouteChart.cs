using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal partial class RouteChart : Control
{
    internal CampaignLog Log = null!;
    internal CampaignArc? Coast;
    internal string Selected = "";
    internal Action<string>? Plot;
    internal Action<int>? Port;
    static readonly Vector2[] Islands = [new(99,109), new(242,197), new(396,106), new(539,174)];
    static readonly Vector2[] Ports = [new(55,189),new(149,210),new(201,141),new(284,172),
        new(346,108),new(434,153),new(495,83),new(578,97),new(618,40)];
    static readonly string[] Names = ["Last Light","Cinder","Reedglass","Orchard","Whitewake","Tangleloom","Choir","Sable","Unnumbered"];
    static readonly string[] OuterNames = ["Last Light","Saltstep","Bottlebrush","Waxwing","Sleeping","Tinmoon","Drumskin","Pitchwake","Calving"];
    static readonly Color Ink = new("364d54"), Faded = new("ad9f7f"), Water = new("dbd6b5"), Marker = new("a3483b");
    static readonly Font ChartFont = new SystemFont {FontNames = ["Baskerville","Georgia","serif"]};
    public override void _Draw()
    {
        var rect = new Rect2(Vector2.Zero, Size);
        DrawRect(rect, Water);
        DrawRect(rect.Grow(-1.5f), new Color("aa8257"), false, 3);
        DrawRect(rect.Grow(-8), new Color("b4a182"), false, 1);
        for (int x=40; x<Size.X-10; x+=42)
            DrawLine(new(x,9),new(x,Size.Y-9),new Color("a6ae9a6a"),1);
        for (int y=31; y<Size.Y-10; y+=42)
            DrawLine(new(9,y),new(Size.X-9,y),new Color("a6ae9a6a"),1);
        if (Coast != null)
        {
            DrawCoast(Coast);
            return;
        }
        DrawString(ChartFont,new(23,39),Log.HomePortNamed?"The Walking Tide":"The Far Ledger",HorizontalAlignment.Left,-1,26,Ink);
        int current = Math.Clamp(1+Log.SettledPorts().Count()-(Log.HomePortNamed?8:0),0,8);
        for (int i=0; i<Ports.Length; i++)
        {
            var p = Ports[i];
            if (i > 0)
                DrawDashedLine(Ports[i-1],p,i<=current ? Marker : Faded,1.7f,5);
            Vector2[] rim = new Vector2[11];
            for (int k=0;k<rim.Length;k++)
            {
                float a=k*Mathf.Tau/rim.Length;
                float radius=11+3*MathF.Cos(4*a+i)+3*MathF.Sin(3*a-i);
                rim[k]=p+new Vector2(MathF.Cos(a)*radius,MathF.Sin(a)*radius*.65f);
            }
            DrawColoredPolygon(rim,i<=current?new("78998c"):new("b0b2a0"));
            DrawCircle(p,i==current?4:2.5f,i==current?Marker:Ink,true,-1,true);
            if (i==current) DrawArc(p,16,0,Mathf.Tau,48,Marker,1.6f,true);
            DrawString(ChartFont,p+new Vector2(-39,i%2==0?24:-16),(Log.HomePortNamed?OuterNames:Names)[i],HorizontalAlignment.Center,78,15,i<=current?Ink:new("6e766b"));
        }
    }

    void DrawCoast(CampaignArc coast)
    {
        DrawString(ChartFont,new(23,39),coast.Region,HorizontalAlignment.Left,-1,26,Ink);
        for (int i=0;i<coast.Islands.Length;i++)
        {
            var island=coast.Islands[i];
            var p=Islands[i%Islands.Length];
            if (i>0) DrawDashedLine(Islands[(i-1)%Islands.Length],p,Faded,1.5f,6);
            int filed=island.Outings.Count(o=>Log.Contains(o.Id));
            bool here=island.Island==Selected;
            Vector2[] rim = new Vector2[19];
            for (int k=0;k<rim.Length;k++)
            {
                float a=k*Mathf.Tau/rim.Length;
                float r=19+5*MathF.Sin(a*(3+i)+i)+3*MathF.Cos(a*2-i);
                rim[k]=p+new Vector2(MathF.Cos(a)*r*(1+i*.09f),MathF.Sin(a)*r*.71f);
            }
            DrawColoredPolygon(rim,here?new("548b80"):new("88a79a"));
            DrawCircle(p,3.5f,here?Marker:Ink);
            if(here) DrawArc(p,29,0,Mathf.Tau,48,Marker,1.6f,true);
            DrawString(ChartFont,p+new Vector2(-85,43),island.Island,HorizontalAlignment.Center,170,16,Ink);
            for(int k=0;k<island.Outings.Length;k++)
            {
                var mark=p+new Vector2((k-(island.Outings.Length-1)/2f)*10,54);
                DrawCircle(mark,2.9f,k<filed?Marker:Faded);
            }
        }
    }
    public override void _GuiInput(InputEvent input)
    {
        if(input is not InputEventMouseButton {Pressed:true, ButtonIndex:MouseButton.Left} click)return;
        if(Coast==null)
        {
            int offset=Log.HomePortNamed?8:0;
            for(int j=1;j<Ports.Length;j++)
                if(click.Position.DistanceSquaredTo(Ports[j])<34*34 && Log.FiledIn(FarLedger.Arcs[offset+j-1])>0)
                {
                    Port?.Invoke(offset+j-1);AcceptEvent();return;
                }
            return;
        }
        for(int i=0;i<Coast.Islands.Length;i++)
        {
            var hit=new Rect2(Islands[i%Islands.Length]-new Vector2(75,31),new(150,91));
            if(!hit.HasPoint(click.Position)) continue;
            Plot?.Invoke(Coast.Islands[i].Island);
            AcceptEvent();
            return;
        }
    }
}
