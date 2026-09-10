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
    float bed=noise(world.xz*6.0)*.65+noise(world.xz*15.0)*.35;
    float submerged=smoothstep(.43,.69,bed);
    vec3 shallow=mix(vec3(.30,.66,.59),vec3(.075,.43,.47),smoothstep(.0,.90,depth));
    shallow=mix(shallow,vec3(.08,.36,.38),submerged*.48);
    float caustic=pow(1.0-abs(sin(world.x*19.0+sin(world.z*13.0+clock*.6))*sin(world.z*17.0-world.x*7.0+clock*.4)),18.0);
    shallow+=vec3(.055,.10,.072)*caustic*(1.0-depth)*.45;

    // Broken wash advances toward sand and dissolves. Integer angle frequencies
    // join seamlessly around the continuous coast coordinates supplied by the mesh.
    float phase=fract(clock*.19+sin(UV.x*3.0)*.13);
    float crest=.035+(1.0-phase)*.29;
    float wiggle=sin(UV.x*29.0+clock*.7)*.011+sin(UV.x*47.0)*.006;
    float breakup=smoothstep(.27,.60,noise(world.xz*21.0+vec2(clock*.06,0.0))*.55+.45*sin(UV.x*11.0)*sin(UV.x*7.0)+.24);
    float wash=(1.0-smoothstep(.008,.036,abs(depth-crest+wiggle)))*sin(phase*3.14159)*breakup;
    float edge=(1.0-smoothstep(.008,.029,abs(depth-.027+wiggle)))*breakup;
    float lace=(1.0-smoothstep(.003,.018,abs(depth-crest-.058+wiggle)))*breakup*.33*sin(phase*3.14159);
    // Broad stationary shoals, with softly missing sections rather than a painted ring.
    // Integer coast frequencies preserve the seam; world noise breaks up the outer edge.
    float coast_patch=.5+.26*sin(UV.x*2.0+1.3)+.18*cos(UV.x*3.0-.7)+.10*sin(UV.x*5.0+.6);
    float shoal=noise(world.xz*1.7)*.65+noise(world.xz*.65)*.35;
    float coverage=smoothstep(.25,.64,coast_patch*.75+shoal*.25);
    float foam=clamp(wash+edge+lace,0.0,1.0)*smoothstep(.12,.7,coverage);
    float shelf_alpha=(1.0-smoothstep(.12,.96,depth+(.5-shoal)*.38))*coverage*.72;
    ALBEDO=linear_color(mix(shallow,vec3(.91,.96,.84),foam));
    ALPHA=max(foam*.84,shelf_alpha);
}
