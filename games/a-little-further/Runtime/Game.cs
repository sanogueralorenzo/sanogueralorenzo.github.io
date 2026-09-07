using Godot;
using Further.Core;
using V2=System.Numerics.Vector2;
namespace Further;
public partial class Game : Node3D
{
    public Run Run {get;private set;}=null!;
    public bool Title=true,Paused,Chart,Cruise;
    public V2? GroundTarget;
    public float FrameMs;
    Node3D world=null!,boat=null!,captain=null!,actors=null!;
    Camera3D camera=null!;
    Islands islands=null!;
    Ocean ocean=null!;
    Effects effects=null!;
    Hud hud=null!;
    Sound sound=null!;
    SourceAnimation animation=null!;
    readonly Dictionary<int,Node3D> foes=[];
    readonly List<Node3D> mates=[];
    readonly HashSet<Key> pressed=[];
    Vector3 look;
    float cameraYaw=Mathf.Pi,shake,sprayClock;
    int seed=1701,previousGold;
    readonly Queue<double> frames=new();
    ulong lastFrameTick;
    string? evidence;
    bool auto,exiting;
    public bool IsValidation=>auto;
    bool travelTest,finished,deathCaptured;
    float stageClock;
    int coinTarget,visitedTargets;
    Cell destination=new(1,0);
    V2[] seaRoute=[];
    int seaWaypoint;
    float autoElapsed;
    int autoStage;
    public override void _Ready()
    {
        GetTree().AutoAcceptQuit=false;
        foreach(string arg in OS.GetCmdlineUserArgs())
        {
            if(arg.StartsWith("--seed="))int.TryParse(arg[7..],out seed);
            if(arg.StartsWith("--evidence="))evidence=arg[11..];
            if(arg=="--autoplay")auto=true;
            if(arg=="--travel-test"){auto=true;travelTest=true;}
        }
        if(evidence!=null)Directory.CreateDirectory(evidence);
        animation=new SourceAnimation();CreateEnvironment();Restart(seed);
        var layer=new CanvasLayer();AddChild(layer);hud=new Hud{Game=this};layer.AddChild(hud);
        sound=new Sound();AddChild(sound);
        if(auto)Title=false;
        if(travelTest){Run.Ship.Position=new(0,-96);Run.Position=Run.Ship.Position;Run.Ship.Heading=MathF.PI/2;}
    }
    public override void _Notification(int what)
    {
        if(what==NotificationWMCloseRequest)Quit();
    }
    async void Quit(int code=0)
    {
        if(exiting)return;exiting=true;sound?.Shutdown();
        // Let the audio mixer consume queued stops before native resource teardown.
        await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(),SceneTree.SignalName.ProcessFrame);
        GetTree().Quit(code);
    }
    void CreateEnvironment()
    {
        var sky=new ProceduralSkyMaterial{SkyTopColor=new("427f92"),SkyHorizonColor=new("d5dec0"),GroundBottomColor=new("366478"),GroundHorizonColor=new("d5dec0"),SkyCurve=.18f,SunAngleMax=8};
        var env=new Godot.Environment{BackgroundMode=Godot.Environment.BGMode.Sky,Sky=new Sky{SkyMaterial=sky},AmbientLightSource=Godot.Environment.AmbientSource.Color,AmbientLightColor=new("bedbd6"),AmbientLightEnergy=.38f,ReflectedLightSource=Godot.Environment.ReflectionSource.Sky,TonemapMode=Godot.Environment.ToneMapper.Aces,FogEnabled=true,FogLightColor=new("a9c9bd"),FogDensity=.0015f,FogSkyAffect=.25f,SsaoEnabled=true,SsaoRadius=1.5f,SsaoIntensity=1.1f,GlowEnabled=true,GlowIntensity=.18f};
        AddChild(new WorldEnvironment{Environment=env});
        AddChild(new DirectionalLight3D{RotationDegrees=new(-38,-32,0),LightColor=new("ffe0a4"),LightEnergy=1.0f,ShadowEnabled=true,DirectionalShadowMaxDistance=130,ShadowBias=.06f});
        camera=new Camera3D{Fov=52,Near=.15f,Far=1250,Position=new(0,12,-106),Current=true};AddChild(camera);
    }
    static void MergeBoat(Node3D model)
    {
        var groups=new Dictionary<Material,SurfaceTool>();
        void Walk(Node n,Transform3D parent)
        {
            var transform=n is Node3D spatial?parent*spatial.Transform:parent;
            if(n is MeshInstance3D m && m.Mesh!=null)
            {
                for(int i=0;i<m.Mesh.GetSurfaceCount();i++)
                {
                    Material mat=m.GetActiveMaterial(i)??Art.Material(Art.Cream);
                    if(!groups.TryGetValue(mat,out var st)){st=new();st.Begin(Mesh.PrimitiveType.Triangles);groups[mat]=st;}
                    st.AppendFrom(m.Mesh,i,transform);
                }
                m.Visible=false;
            }
            foreach(Node child in n.GetChildren())Walk(child,transform);
        }
        Walk(model,Transform3D.Identity);
        foreach(Node original in model.GetChildren())original.QueueFree();
        foreach(var (material,st) in groups){var mesh=st.Commit();st.Dispose();model.AddChild(new MeshInstance3D{Mesh=mesh,MaterialOverride=material});}
        GD.Print($"Boat consolidated into {groups.Count} material draws.");
    }
    public void Restart(int? newSeed=null)
    {
        if(world!=null){SaveMetrics();RemoveChild(world);world.QueueFree();}
        world=new Node3D{Name="RunWorld"};AddChild(world);Run=new(newSeed??Random.Shared.Next(1,int.MaxValue),SourceTuning.Load());
        actors=new Node3D();world.AddChild(actors);foes.Clear();mates.Clear();
        islands=new(world,Run);ocean=new(world);effects=new(world);
        boat=new Node3D();world.AddChild(boat);
        using var doc=new GltfDocument();using var state=new GltfState();var error=doc.AppendFromFile(Art.Local("boat.glb"),state);
        if(error!=Error.Ok)throw new IOException("Recovered Sunwake boat could not load: "+error);
        var boatModel=(Node3D)doc.GenerateScene(state);boat.AddChild(boatModel);MergeBoat(boatModel);Art.SailingRig(boat);
        captain=Art.Pirate(actors,Art.Coral);
        cameraYaw=Mathf.Pi;camera.Position=Art.At(Run.Position,12)+new Vector3(0,0,-22);look=Art.At(Run.Position,2);
        Run.Shifted+=()=>{var s=Run.LastShift;islands.Shift();ocean.Shift(s);effects.Shift(s);camera.Position-=Art.At(s,0);look-=Art.At(s,0);};
        Paused=false;Cruise=false;GroundTarget=null;previousGold=0;autoStage=0;autoElapsed=0;stageClock=0;coinTarget=0;frames.Clear();
    }
    public override void _Input(InputEvent e)
    {
        if(exiting)return;
        if(e is InputEventKey k && k.Pressed && !k.Echo)
        {
            pressed.Add(k.Keycode);
            if(k.Keycode==Key.Escape){if(Title)Quit();else Paused=!Paused;}
            if(k.Keycode==Key.Tab)Chart=!Chart;
            if(k.Keycode==Key.C && Run.Mode==RunMode.Sailing)Cruise=!Cruise;
            if(Title && k.Keycode is Key.Enter or Key.Space){Title=false;sound.Cue(0);}
            else if(Run.Mode==RunMode.Dead && k.Keycode==Key.Enter){Restart();sound.Cue(0);}
            else if(Run.Mode==RunMode.Choosing && k.Keycode>=Key.Key1 && k.Keycode<=Key.Key3){Run.Choose((int)(k.Keycode-Key.Key1),Run.SelectedReplacement);sound.Cue(0);}
            else if(Run.Mode==RunMode.Choosing && k.Keycode==Key.R)Run.SelectedReplacement=(Run.SelectedReplacement+1)%4;
            if(k.Keycode==Key.F12)Capture("manual");
        }
        if(e is InputEventMouseButton mb && mb.Pressed && mb.ButtonIndex==MouseButton.Left)
        {
            if(!Title && !Paused && !Chart && Run.Mode==RunMode.Exploring && mb.Position.Y<GetViewport().GetVisibleRect().Size.Y-125)
            {
                Vector3 origin=camera.ProjectRayOrigin(mb.Position),direction=camera.ProjectRayNormal(mb.Position);
                for(float t=1;t<250;t+=.4f){var p=origin+direction*t;var q=new V2(p.X,p.Z);if(p.Y<=Run.World.Height(q)){GroundTarget=q;break;}}
            }
            else hud.Click(mb.Position);
        }
    }
    bool Down(Key key)=>Input.IsPhysicalKeyPressed(key);
    public override void _PhysicsProcess(double delta)
    {
        float dt=(float)delta;
        if(exiting||Title||Paused){pressed.Clear();return;}
        var input=InputCommand();
        if(auto)input=Pilot(dt);
        Run.Tick(dt,input);pressed.Clear();
        if(Run.Gold>previousGold)sound.Cue(1);previousGold=Run.Gold;
        foreach(var hit in Run.Hits){effects.Shot(hit,Run);sound.Cue(hit.Kind<0?3:2);shake=MathF.Max(shake,hit.Kind<0?.22f:.045f);}
        if(auto && evidence!=null && autoElapsed>600){Capture("timeout");SaveMetrics();Quit(2);}
    }
    Command InputCommand()
    {
        float x=(Down(Key.D)||Down(Key.Right)?1:0)-(Down(Key.A)||Down(Key.Left)?1:0);
        float y=(Down(Key.W)||Down(Key.Up)?1:0)-(Down(Key.S)||Down(Key.Down)?1:0);
        if(Run.Mode!=RunMode.Sailing)
        {
            if(MathF.Abs(x)+MathF.Abs(y)>.01f)GroundTarget=null;
            Vector3 forward=-camera.GlobalBasis.Z;forward.Y=0;forward=forward.Normalized();Vector3 right=camera.GlobalBasis.X;right.Y=0;right=right.Normalized();var d=forward*y+right*x;x=d.X;y=d.Z;
        }
        // The source helm uses negative steer for clockwise rotation.
        else {x=-x;if(y==0 && Cruise)y=1;if(Down(Key.S))Cruise=false;}
        if(Run.Mode==RunMode.Exploring && GroundTarget is V2 target)
        {
            var d=target-Run.Position;if(d.Length()<.7f)GroundTarget=null;else{x=d.X/d.Length();y=d.Y/d.Length();}
        }
        return new(new(x,y),pressed.Contains(Key.Shift),pressed.Contains(Key.Space),Down(Key.Space),pressed.Contains(Key.E),Down(Key.Shift),pressed.Contains(Key.F));
    }
    public override void _Process(double delta)
    {
        if(Run==null||exiting)return;
        ulong tick=Godot.Time.GetTicksUsec();double measuredMs=lastFrameTick==0?delta*1000:(tick-lastFrameTick)/1000.0;lastFrameTick=tick;
        float dt=(float)delta;FrameMs+=(dt*1000-FrameMs)*.06f;if(evidence!=null && !Title&&!Paused && Run.Mode!=RunMode.Dead){frames.Enqueue(measuredMs);if(frames.Count>60000)frames.Dequeue();}
        islands.Step(camera);ocean.Update(Run);effects.Step(Paused?0:dt);
        boat.Position=Art.At(Run.Ship.Position,Run.Ship.Height);boat.Rotation=new(-Run.Ship.Pitch,Run.Ship.Heading,Run.Ship.Roll);
        bool aboard=Run.Mode==RunMode.Sailing;captain.Visible=!aboard;
        captain.Position=Art.At(Run.Position,Run.Height+.04f+animation.Bob((float)Run.Time,Run.Velocity.Length()));
        var wings=captain.GetNode<Node3D>("GlideWings");wings.Visible=Run.IsGliding;wings.Scale=animation.Wings((float)Run.Time)*.9f;captain.Rotation=new(0,Run.Heading,MathF.Sin((float)Run.Time*12)*MathF.Min(.07f,Run.Velocity.Length()*.01f));
        while(mates.Count<Run.Crew.Count)mates.Add(Art.Pirate(actors,RoleColor(Run.Crew[mates.Count].Role),.75f));
        for(int i=0;i<mates.Count;i++)
        {
            if(!mates[i].HasMeta("role") || mates[i].GetMeta("role").AsInt32()!=(int)Run.Crew[i].Role)
            {
                mates[i].QueueFree();mates[i]=Art.Pirate(actors,RoleColor(Run.Crew[i].Role),.75f);mates[i].SetMeta("role",(int)Run.Crew[i].Role);mates[i].Position=Art.At(Run.Position,Run.Height);
            }
            var mate=mates[i];mate.Visible=!aboard;float angle=i*2.4f+(float)Run.Time*.15f;
            V2 p=Run.Position+new V2(MathF.Sin(angle),MathF.Cos(angle))*2.6f;float h=Run.World.Height(p);
            mate.Position=mate.Position.Lerp(Art.At(p,h+.06f),1-MathF.Exp(-7*dt));mate.Rotation=new(0,Run.Heading,MathF.Sin((float)Run.Time*10+i)*.07f);
        }
        foreach(int key in foes.Keys.Where(id=>Run.Enemies.All(e=>e.Id!=id)).ToArray()){foes[key].QueueFree();foes.Remove(key);}
        foreach(var e in Run.Enemies)
        {
            if(!foes.TryGetValue(e.Id,out var n)){n=Art.Monster(actors,e.Kind);foes[e.Id]=n;}
            n.Position=Art.At(e.Position,Run.World.Height(e.Position)+.05f);n.Rotation=new(0,MathF.Atan2(Run.Position.X-e.Position.X,Run.Position.Y-e.Position.Y),MathF.Sin((float)Run.Time*7+e.Id)*.08f);
            n.Scale=Vector3.One*(e.Kind==1?1.35f:1)*(e.Flash>0?1.13f:1);
        }
        sprayClock-=dt;if(aboard&&Run.Ship.Velocity.Length()>8 && sprayClock<0){sprayClock=.09f;var f=new Vector3(MathF.Sin(Run.Ship.Heading),0,MathF.Cos(Run.Ship.Heading));effects.Burst(boat.Position+f*2.5f,Art.Cream,2,1.4f);}
        UpdateCamera(dt);hud.QueueRedraw();sound.SetSea(aboard?Run.Ship.Velocity.Length()/20:.1f);
    }
    void UpdateCamera(float dt)
    {
        if(Paused)return;
        bool aboard=Run.Mode==RunMode.Sailing || Title;
        if(aboard)cameraYaw=Mathf.LerpAngle(cameraYaw,Run.Ship.Heading+Mathf.Pi,1-MathF.Exp(-1.7f*dt));
        else{if(Down(Key.Q))cameraYaw+=dt*1.5f;if(Down(Key.R))cameraYaw-=dt*1.5f;}
        float distance=aboard?23+Run.Ship.Velocity.Length()*.25f:18;
        Vector3 target=Art.At(Run.Position,aboard?1.6f:Run.Height+1.1f);
        if(Title)target-=camera.GlobalBasis.X*8;
        Vector3 wanted=target+new Vector3(MathF.Sin(cameraYaw)*distance,aboard?12:18,MathF.Cos(cameraYaw)*distance);
        wanted.Y=MathF.Max(wanted.Y,Run.World.Height(new(wanted.X,wanted.Z))+6);
        // Sunwake chase interpolation: 4.5 position / 5.4 focus exponential response.
        var blend=PrivateSources.ChaseBlend(dt);camera.Position=camera.Position.Lerp(wanted,blend.Position);look=look.Lerp(target,blend.Focus);
        shake*=MathF.Exp(-8*dt);camera.LookAt(look+new Vector3(MathF.Sin((float)Run.Time*71)*shake,MathF.Cos((float)Run.Time*59)*shake,0));
    }
    public static Color RoleColor(Role role)=>role switch{Role.Gunner=>new("c79b5c"),Role.Stormcaller=>new("68abb5"),Role.Cook=>new("abb96b"),Role.Duelist=>new("cc806d"),Role.Harpooner=>new("b7a0bc"),_=>new("83c1ab")};
    public Camera3D Camera=>camera;
    public int LoadedChunks=>islands.Loaded.Count;
    public void Start(){Title=false;sound.Cue(0);}
    public void Select(int i){Run.Choose(i,Run.SelectedReplacement);sound.Cue(0);}
    async void Capture(string name)
    {
        string dir=evidence??ProjectSettings.GlobalizePath("res://captures");Directory.CreateDirectory(dir);
        await ToSignal(RenderingServer.Singleton,RenderingServer.SignalName.FramePostDraw);
        string file=Path.Combine(dir,$"{name}-{Run.World.Seed}-{(int)Run.Time:000}.png");using var captureImage=GetViewport().GetTexture().GetImage();captureImage.SavePng(file);GD.Print("CAPTURE "+file);
    }
    void SaveMetrics()
    {
        if(evidence==null)return;var sorted=frames.Skip(120).Order().ToArray();if(sorted.Length==0)return;
        File.WriteAllText(Path.Combine(evidence,$"metrics-{Run.World.Seed}.json"),System.Text.Json.JsonSerializer.Serialize(new {seed=Run.World.Seed,seconds=Run.Time,mode=Run.Mode.ToString(),Run.Gold,Run.Kills,Run.Shrines,Run.IslandsVisited,Run.ShiftCount,loaded=islands.Loaded.Count,frames=sorted.Length,medianMs=sorted[sorted.Length/2],p95Ms=sorted[(int)(sorted.Length*.95)],p99Ms=sorted[(int)(sorted.Length*.99)],sampleKind="monotonic process callback interval",recordedMovie=Engine.GetWriteMoviePath().Length>0,renderer=RenderingServer.GetCurrentRenderingMethod(),adapter=RenderingServer.GetVideoAdapterName(),drawCalls=Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame),objects=Performance.GetMonitor(Performance.Monitor.RenderTotalObjectsInFrame),processMs=Performance.GetMonitor(Performance.Monitor.TimeProcess)*1000,physicsMs=Performance.GetMonitor(Performance.Monitor.TimePhysicsProcess)*1000},new System.Text.Json.JsonSerializerOptions{WriteIndented=true}));
    }
    public override void _ExitTree(){if(Run!=null)SaveMetrics();}
    Command Pilot(float dt)
    {
        autoElapsed+=dt;stageClock+=dt;
        if(travelTest)
        {
            if(autoElapsed>5 && autoStage==0){Capture("travel-start");autoStage=1;}
            if(autoElapsed>180){Capture("travel-end");SaveMetrics();Quit();}
            return new(new(0,1),Boost:true);
        }
        if(finished){if(stageClock>1 && autoStage!=99){Capture("09-fresh-run");autoStage=99;}if(stageClock>3)Quit();return new();}
        if(Run.Mode==RunMode.Dead)
        {
            if(!deathCaptured){Capture("08-death");SaveMetrics();deathCaptured=true;stageClock=0;}
            if(stageClock>3){Restart(Run.World.Seed+1);finished=true;stageClock=0;}
            return new();
        }
        Command Walk(V2 target,bool interact=false)
        {
            var d=target-Run.Position;
            return new(d.Length()>.6f?V2.Normalize(d):V2.Zero,Jump:stageClock%2<dt,HoldJump:true,Interact:interact);
        }
        void Stage(int number){autoStage=number;stageClock=0;}
        if(autoStage==0)
        {
            if(Run.CanLand){Stage(1);Capture("01-arrival");return new(V2.Zero,Interact:true);}
            return new(new(0,1));
        }
        if(autoStage==1 && Run.Current!=null)
        {
            if(coinTarget<8)
            {
                var target=Run.TreasureAt(coinTarget);
                if(V2.Distance(Run.Position,target)<1.7f)coinTarget++;
                return Walk(target);
            }
            if(V2.Distance(Run.Position,Run.Current.Shrine)<3){Stage(2);Capture("02-shrine");return new(V2.Zero,Interact:true);}
            return Walk(Run.Current.Shrine);
        }
        if(autoStage==2 && Run.Current!=null)
        {
            if(Run.Mode==RunMode.Choosing){Stage(3);Capture("04-crew-choice");return new();}
            if(stageClock>10 && stageClock<10+dt*2)Capture("03-combat");
            if(visitedTargets>=2)return new();
            float a=(float)Run.Time*.4f;var d=Run.Current.Shrine+new V2(MathF.Sin(a),MathF.Cos(a))*5-Run.Position;
            return new(d.Length()>.3f?V2.Normalize(d):V2.Zero,Dodge:Run.DodgeCooldown<=0 && Run.Enemies.Any(e=>e.Windup>0));
        }
        if(autoStage==3)
        {
            if(stageClock<3)return new();
            int choice=Array.FindIndex(Run.Offers,role=>!Run.Crew.Any(m=>m.Role==role));Run.Choose(choice>=0?choice:0);Stage(4);return new();
        }
        if(autoStage==4 && Run.Current!=null)
        {
            if(V2.Distance(Run.Position,Run.Current.Landing)<3){Capture("05-return");Run.Provision();
                var nextIsland=Run.World.IslandAt(destination);
                seaRoute=[Run.Current.Center+new V2(0,-85),Run.Current.Center+new V2(90,-85),nextIsland.Center+new V2(90,-85),nextIsland.Landing];seaWaypoint=0;
                Stage(5);return new(V2.Zero,Interact:true);}
            return Walk(Run.Current.Landing);
        }
        if(autoStage==5)
        {
            Island island=Run.World.IslandAt(destination);
            if(seaWaypoint<seaRoute.Length-1 && V2.Distance(Run.Position,seaRoute[seaWaypoint])<14)seaWaypoint++;
            var d=(seaRoute.Length>0?seaRoute[seaWaypoint]:island.Landing)-Run.Position;
            if(Run.Nearest.Cell==destination && Run.CanLand)
            {
                visitedTargets++;destination=new(destination.X, destination.Z+1);coinTarget=0;Stage(1);Capture("06-new-island");return new(V2.Zero,Interact:true);
            }
            float desired=MathF.Atan2(d.X,d.Y),error=MathF.Atan2(MathF.Sin(desired-Run.Ship.Heading),MathF.Cos(desired-Run.Ship.Heading));
            float throttle=MathF.Abs(error)>1.0f?0:MathF.Abs(error)>.45f?.35f:1;
            return new(new(Math.Clamp(-error*2,-1,1),throttle),Boost:d.Length()>50);
        }
        return new();
    }
}
