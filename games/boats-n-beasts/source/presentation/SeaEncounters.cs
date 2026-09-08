using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Original world-space encounter art; the ocean node supplies the shared camera projection.
public sealed class SeaEncounters(Node2D canvas)
{
    static readonly Color Wood = new("ac784b"), Gold = new("efc46d"), Dark = new("153642");
    void Poly(Vector2[] points, Color color) => canvas.DrawColoredPolygon(points,color);
    public void Draw(Place place, Vector2 at, float clock, bool depleted)
    {
        if(place.Kind==PlaceKind.Current)
        {
            float angle=OceanView.G(OceanWorld.FlowDirection(place)).Angle();
            canvas.DrawSetTransform(at,angle);
            for(int lane=-1;lane<=1;lane++) for(int i=0;i<5;i++)
            {
                float x=((i*98+clock*65+lane*23)%490)-245;
                float alpha=Mathf.Clamp(1-Mathf.Abs(x)/245,0,1)*.35f;
                float y=lane*35+Mathf.Sin(x*.02f+lane)*3;
                canvas.DrawPolyline([new(x-15,y-5),new(x,y),new(x-15,y+5)],new Color(OceanView.Aqua,alpha),2.5f,true);
                canvas.DrawLine(new(x-45,y),new(x-24,y),new Color(OceanView.Aqua,alpha*.45f),2,true);
            }
            canvas.DrawSetTransform(Vector2.Zero); return;
        }
        if(depleted) return;
        canvas.DrawSetTransform(at+new Vector2(0,Mathf.Sin(clock*2+place.Style%11)*2),place.Kind==PlaceKind.Wreck?.2f:0, Vector2.One * (place.Kind==PlaceKind.Treasure?1.35f:1));
        if(place.Kind==PlaceKind.Treasure)
        {
            canvas.DrawCircle(new(0,2),28,new Color(Gold,.08f));
            canvas.DrawArc(new(0,8),27,.1f,Mathf.Pi-.1f,20,new Color(Gold,.65f),2,true);
            Poly([new(-20,-6),new(-13,-17),new(9,-19),new(21,-7),new(18,15),new(-16,17)],Dark);
            Poly([new(-18,-6),new(-11,-15),new(9,-17),new(18,-7),new(15,-1),new(-17,1)],Wood.Lightened(.22f));
            Poly([new(-17,2),new(15,0),new(15,14),new(-15,16)],Wood);
            Poly([new(15,0),new(20,-7),new(18,13),new(15,14)],Wood.Darkened(.3f));
            canvas.DrawPolyline([new(-10,15),new(-11,-7),new(-7,-15)],Gold,3,true);
            canvas.DrawPolyline([new(9,14),new(10,-6),new(6,-16)],Gold,3,true);
            canvas.DrawLine(new(-17,2),new(15,0),Gold.Darkened(.2f),2,true);
            canvas.DrawRect(new Rect2(-3,0,6,6),Gold);
            float glint=.65f+.3f*Mathf.Sin(clock*3);
            canvas.DrawLine(new(-6,-19),new(6,-19),new Color(OceanView.Cream,glint),2);
            canvas.DrawLine(new(0,-25),new(0,-13),new Color(OceanView.Cream,glint),2);
        }
        else
        {
            Poly([new(-61,-12),new(-22,-29),new(34,-23),new(64,6),new(22,26),new(-38,23)],new Color(Dark,.65f));
            Poly([new(-56,-11),new(-22,-25),new(-5,-18),new(-12,-8),new(12,-4),new(6,13),new(-29,20),new(-49,12)],Wood);
            Poly([new(13,-18),new(36,-19),new(58,6),new(24,22),new(16,7),new(29,1)],Wood.Darkened(.2f));
            for(int i=-2;i<=2;i++) canvas.DrawLine(new(i*17,-18),new(i*17+7,16),Gold.Darkened(.3f),3,true);
            canvas.DrawLine(new(-9,7),new(8,-78),Dark,5,true);
            Poly([new(7,-71),new(43,-36),new(23,-39),new(28,-18),new(4,-29)],new Color(OceanView.Cream,.8f));
            canvas.DrawArc(new(0,9),66,.1f,2.6f,28,new Color(OceanView.Aqua,.35f),2,true);
        }
        canvas.DrawSetTransform(Vector2.Zero);
    }
}
