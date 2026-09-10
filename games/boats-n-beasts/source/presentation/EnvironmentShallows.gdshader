shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float clock = 0.0;
varying vec3 world;

vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
    vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    float depth=UV.y;
    // Broad sandbanks beneath quiet water, with just a trace of smaller reef detail.
    vec2 warp=vec2(noise(world.xz*.65),noise(world.zx*.65+17.0))-.5;
    float shoal=noise(world.xz*2.6+warp)*.72+noise(world.xz*5.5)*.28;
    float reef=smoothstep(.40,.69,shoal);
    vec3 shallow=mix(vec3(.30,.65,.59),vec3(.075,.43,.47),smoothstep(.0,.95,depth));
    shallow=mix(shallow,vec3(.10,.39,.40),reef*.44*(1.0-depth*.6));
    float caustic=pow(1.0-abs(sin(world.x*13.0+sin(world.z*9.0+clock*.6))*sin(world.z*11.0-world.x*5.0+clock*.4)),18.0);
    shallow+=vec3(.045,.08,.06)*caustic*(1.0-depth)*.20;

    // Independent, softly dissolving wash segments avoid concentric white rings.
    // Integer angle frequencies keep the mesh seam continuous.
    float phase=fract(clock*.17+sin(UV.x*2.0)*.19+sin(UV.x*5.0)*.10);
    float crest=.025+(1.0-phase)*.23;
    float wiggle=sin(UV.x*17.0+clock*.5)*.008;
    float breakup=smoothstep(.47,.66,noise(world.xz*2.8)*.65+noise(world.xz*7.0)*.35);
    float wash=(1.0-smoothstep(.004,.019,abs(depth-crest+wiggle)))*sin(phase*3.14159)*breakup;
    float edge=(1.0-smoothstep(.004,.020,abs(depth-.025+wiggle)))*breakup;
    float foam=clamp(wash*.90+edge*.52,0.0,1.0);
    // Maintain the visible inner shelf. Only the outer edge dissolves into deep water.
    float shelf_alpha=(1.0-smoothstep(.30,1.0,depth+(.5-shoal)*.24))*mix(1.0,.86,smoothstep(.03,.24,depth));
    ALBEDO=linear_color(mix(shallow,vec3(.91,.96,.84),foam));
    ALPHA=max(foam*.84,shelf_alpha);
}
