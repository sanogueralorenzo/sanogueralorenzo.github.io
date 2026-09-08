using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Runtime-only animation strips, rendered from our own procedural geometry.
// One textured quad per creature replaces hundreds of individual polygon submissions.
public partial class CreatureAtlas : Node
{
    const int Frames = 24;
    readonly Dictionary<EnemyKind, SubViewport> strips = new();
    static int Cell(EnemyKind kind) => kind == EnemyKind.Leviathan ? 320 : 160;
    static float Height(EnemyKind kind) => kind == EnemyKind.Leviathan ? 230 : kind == EnemyKind.Serpent ? 119 : kind == EnemyKind.Ray ? 115 : 95;
    static float Duration(EnemyKind kind) => Mathf.Tau / (kind == EnemyKind.Serpent ? 3 : kind == EnemyKind.Ray ? 4 : kind == EnemyKind.Puffer ? 8 : 5);
    public override void _Ready()
    {
        foreach (EnemyKind kind in Enum.GetValues<EnemyKind>())
        {
            int cell = Cell(kind) * 2;
            var viewport = new SubViewport { Size = new(cell * Frames, cell), TransparentBg = true, Disable3D = true, RenderTargetUpdateMode = SubViewport.UpdateMode.Once };
            AddChild(viewport); viewport.AddChild(new Strip { Kind = kind }); strips.Add(kind, viewport);
        }
    }
    public void Draw(Node2D canvas, Enemy enemy, Vector2 position, float facing)
    {
        int cell = Cell(enemy.Kind), frame = (int)(enemy.Time / Duration(enemy.Kind) * Frames) % Frames;
        float rotation = enemy.Kind == EnemyKind.Serpent ? facing : enemy.Kind == EnemyKind.Ray ? facing + Mathf.Pi / 2 : 0;
        float emergence = Math.Clamp(enemy.Time / Enemy.EmergenceDuration, 0, 1);
        canvas.DrawSetTransform(position, rotation, Vector2.One * (.7f + .3f * emergence));
        var color = enemy.HitFlash > 0 ? new Color(1.5f, 1.5f, 1.35f) : Colors.White;
        color.A = emergence;
        canvas.DrawTextureRectRegion(strips[enemy.Kind].GetTexture(), new Rect2(-cell / 2f, -cell / 2f, cell, cell), new Rect2(frame * cell * 2, 0, cell * 2, cell * 2), color);
        canvas.DrawSetTransform(Vector2.Zero);
    }
    partial class Strip : Node2D
    {
        public EnemyKind Kind;
        public override void _Draw()
        {
            var art = new ProceduralArt(this); int cell = Cell(Kind) * 2;
            for (int i = 0; i < Frames; i++) art.Monster(new(cell * (i + .5f), cell * .5f), Height(Kind) * 2, Kind, Duration(Kind) * i / Frames);
        }
    }
}
