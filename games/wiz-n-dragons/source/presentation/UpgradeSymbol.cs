using Godot;
namespace WizNDragons;

public partial class UpgradeSymbol : Control
{
    public int Kind { get; init; }
    public override void _Draw() => DrawSymbol(this, Kind, MagicPalette.Aqua);
    public static void DrawSymbol(CanvasItem canvas, int kind, Color c)
    {
        void Line(float x, float y, float u, float v) => canvas.DrawLine(new(x, y), new(u, v), c, 2, true);
        void Ring(float x, float y, float r) => canvas.DrawArc(new(x, y), r, 0, Mathf.Tau, 32, c, 2, true);
        switch (kind)
        {
            case 0: Ring(23, 19, 9); Line(6, 33, 16, 24); Line(5, 23, 11, 19); break;
            case 1: Line(8, 32, 31, 9); Line(18, 9, 31, 9); Line(31, 9, 31, 22); break;
            case 2: canvas.DrawPolyline([new(20,4),new(35,20),new(20,36),new(5,20),new(20,4)],c,2,true); Ring(20,20,6); break;
            case 3: canvas.DrawPolyline([new(24, 4), new(11, 23), new(23, 23), new(17, 37), new(32, 16), new(21, 16)], c, 2, true); break;
            case 4: Ring(20, 20, 15); Ring(20, 20, 9); Ring(20, 20, 3); break;
            case 5: Ring(20,20,9); canvas.DrawPolyline([new(20,3),new(24,14),new(36,20),new(24,26),new(20,37),new(16,26),new(4,20),new(16,14),new(20,3)],c,2,true); break;
            case 6: canvas.DrawPolyline([new(8, 7), new(32, 7), new(30, 26), new(20, 35), new(10, 26), new(8, 7)], c, 2, true); break;
            case 7: Line(8, 10, 20, 20); Line(20, 20, 8, 30); Line(21, 10, 33, 20); Line(33, 20, 21, 30); break;
            case 8: canvas.DrawArc(new(20, 20), 13, .4f, 5.6f, 32, c, 2, true); Line(30, 7, 32, 17); Line(32, 17, 22, 14); break;
            case 9: Ring(20, 20, 10); Line(20, 3, 20, 11); Line(20, 29, 20, 37); Line(3, 20, 11, 20); Line(29, 20, 37, 20); break;
        }
    }
}
