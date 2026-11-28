using Godot;

namespace BoatsNBeasts;

internal partial class CrewPortrait : SubViewportContainer
{
    Func<Node3D> sculpture = null!;
    internal static CrewPortrait? For(string byline)
    {
        Func<Node3D>? portrait = byline switch
        {
            var name when name.StartsWith("LIO ",StringComparison.Ordinal) => () => ActorArt3D.LandingParty(1),
            var name when name.StartsWith("VARA ",StringComparison.Ordinal) => () => ActorArt3D.LandingParty(2),
            var name when name.StartsWith("NELL",StringComparison.Ordinal) => ActorArt3D.NellSpindle,
            _ => null
        };
        for (int i=0; portrait==null && i<Visitors.All.Length; i++)
        {
            int guest = i;
            if (byline.StartsWith(Visitors.All[i].Name.Split(' ')[0],StringComparison.OrdinalIgnoreCase))
                portrait = () => ActorArt3D.Visitor(guest);
        }
        return portrait == null ? null : new CrewPortrait { sculpture=portrait, Stretch=true,
            CustomMinimumSize=new(132,142), SizeFlagsVertical=Control.SizeFlags.ShrinkCenter,
            MouseFilter=Control.MouseFilterEnum.Ignore };
    }
    public override void _Ready()
    {
        var view = new SubViewport { Size = new(132,142), World3D = new World3D(),
            RenderTargetUpdateMode=SubViewport.UpdateMode.Once, Msaa3D=Viewport.Msaa.Msaa4X,
            HandleInputLocally=false };
        AddChild(view);
        view.World3D.Environment = new Godot.Environment { BackgroundMode=Godot.Environment.BGMode.Color,
            BackgroundColor=new("28505a"), AmbientLightSource=Godot.Environment.AmbientSource.Color,
            AmbientLightColor=new("d5c0c7"), AmbientLightEnergy=.7f };
        var actor = sculpture(); view.AddChild(actor);
        var camera = new Camera3D { Projection=Camera3D.ProjectionType.Orthogonal, Size=.87f, Current=true,
            Position=new(-.35f,.86f,-2.21f) };
        view.AddChild(camera); camera.LookAt(new(0,.67f,0),Vector3.Up);
        var sunlight = new DirectionalLight3D { Position=new(-1.5f,2,-2), LightColor=new("ffe4ba"), LightEnergy=1.2f };
        view.AddChild(sunlight); sunlight.LookAt(new(0,.55f,0),Vector3.Up);
    }
}
