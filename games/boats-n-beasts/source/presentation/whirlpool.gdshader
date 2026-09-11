shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float clock = 0.0;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
// Linear triangular interpolation retains broad, angular patches like painted low-poly water.
float facets(vec2 p) {
    vec2 cell=floor(p), f=fract(p);
    float a=hash(cell), b=hash(cell+vec2(1,0)), c=hash(cell+vec2(0,1)), d=hash(cell+vec2(1,1));
    return f.x+f.y<1.0 ? a+(b-a)*f.x+(c-a)*f.y : d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
void fragment() {
    float r=length(UV), angle=atan(UV.y,UV.x);
    float turn=angle+clock*.18;
    vec2 drift=vec2(cos(turn),sin(turn));
    vec2 field=drift*r*10.0;
    float patch=facets(field+vec2(3.1,7.8));
    float wall=smoothstep(.18,.49,r);
    vec3 color=mix(vec3(.035,.35,.42),vec3(.07,.44,.49),wall);
    color+=vec3(.09,.18,.16)*(patch-.40);
    float water_patch=facets(field*1.55+vec2(6.4,1.7));
    color+=vec3(.035,.075,.07)*(water_patch-.35)*(1.0-smoothstep(.83,1.0,r));
    // Finite, overlapping sweeps taper to nothing: no complete rings or repeated dots.
    for(int i=0;i<6;i++) {
        float lane=float(i);
        float theta=mod(angle+clock*(.17+lane*.012)-lane*2.399,6.2831853);
        float span=3.7+mod(lane,3.0)*.48;
        float u=theta/span;
        float taper=smoothstep(0.0,.36,theta)*(1.0-smoothstep(span-.65,span,theta));
        float radius=.30+lane*.112+.16*(.5-u)+.016*sin(theta*2.0+lane)+(patch-.5)*.016;
        float width=(.020+.023*sin(clamp(u,0.0,1.0)*3.14159265))*(.60+1.05*patch)*(lane<3.0 ? 1.5 : 1.2);
        float wash=(1.0-smoothstep(width*.7,width*2.6,abs(r-radius)))*taper;
        color=mix(color,vec3(.17,.59,.57),wash*(.22+.20*water_patch));
        float band=(1.0-smoothstep(width*.60,width,abs(r-radius)))*taper;
        float strength=(lane>3.0 ? .60 : 1.06)*(.35+.65*patch);
        color=mix(color,vec3(.28,.72,.65)+vec3(.035,.06,.045)*(patch-.5),clamp(band*strength,0.0,.95));
        float glint=(1.0-smoothstep(.003,.009,abs(r-radius-width*.42)))*taper*smoothstep(.35,.72,patch);
        color=mix(color,vec3(.55,.85,.73),glint*.28);
    }
    // The center remains deep teal; irregular water facets continue down the bowl.
    color=mix(vec3(.035,.34,.41)+vec3(.03,.065,.065)*patch,color,smoothstep(.13,.29,r));
    ALBEDO=linear_color(color);
    float reach=r+(facets(field*.65)-.5)*.07*smoothstep(.78,1.0,r);
    ALPHA=1.0-smoothstep(.86,1.0,reach);
}
