using Godot;

namespace CozySora;

public partial class CozyPlayer
{
    private static void Plumage(Node3D joint, int side, bool primaries, StandardMaterial3D material)
    {
        var mesh = new SurfaceTool();
        mesh.Begin(Mesh.PrimitiveType.Triangles);
        var mantle = new Color("9aa5af");
        var ink = new Color("333943");
        var ivory = new Color("eceee9");
        void Feather(Vector3 start, Vector3 end, float width, Color baseColor, Color tipColor)
        {
            var shaft = end - start;
            var across = Vector3.Up.Cross(shaft).Normalized();
            void Point(int row, int vane)
            {
                float t = row / 10f;
                float span = Mathf.Pow(Mathf.Max(0, Mathf.Sin(Mathf.Pi * t)), .65f) * width;
                var at = start + shaft * t + across * (vane * span);
                at.Y += .024f * Mathf.Sin(t * Mathf.Pi) - .005f * Mathf.Abs(vane) - .008f * t * t;
                var pigment = baseColor.Lerp(tipColor, Mathf.SmoothStep(.74f, .97f, t));
                pigment = vane == 0 ? pigment.Lightened(.13f) : pigment.Darkened(.07f);
                mesh.SetNormal((Vector3.Up + across * (vane * .18f) + shaft.Normalized() * (.12f * t)).Normalized());
                mesh.SetColor(pigment.SrgbToLinear());
                mesh.AddVertex(at);
            }
            for (int row = 0; row < 10; row++)
                for (int vane = -1; vane < 1; vane++)
                {
                    Point(row, vane); Point(row + 1, vane); Point(row, vane + 1);
                    Point(row, vane + 1); Point(row + 1, vane); Point(row + 1, vane + 1);
                }
        }

        if (side == 0)
        {
            for (int i = -5; i <= 5; i++)
                Feather(new(i * .003f, 0, 0), new(i * .018f, -.012f, -.18f + Mathf.Abs(i) * .006f), .021f, ivory, ivory);
        }
        else
        {
            for (int i = 0; i < 11; i++)
            {
                float t = i / 10f;
                float x = primaries ? t * .18f : t * .33f;
                var root = new Vector3(side * x, -.002f * t, .055f - t * .012f);
                var tip = primaries ? new Vector3(side * (.08f + t * .35f), -.015f * t, -.155f - .028f * t)
                    : new Vector3(side * (.035f + t * .36f), 0, -.19f + .043f * t);
                var grey = primaries ? mantle.Lerp(ink, Mathf.SmoothStep(.22f, .88f, t)) : mantle;
                Feather(root, tip, primaries ? .028f : .032f, grey, ivory);
                root.Y += .008f;
                Feather(root + Vector3.Back * .014f, root.Lerp(tip, .61f), .034f, mantle.Lightened(.08f), grey);
            }
        }
        mesh.Index();
        CozyPrimitives.Instance(joint, mesh.Commit(), Vector3.Zero, material);
    }
}
