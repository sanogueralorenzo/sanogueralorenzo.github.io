shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float clock = 0.0;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(float p) { return fract(sin(p*127.1)*43758.5453); }
// Linear knots make slanted, chipped edges along the current, rather than cloudy surface noise.
float edge(float t, float seed) {
    float k=floor(t);
    return mix(hash(k+seed),hash(k+1.0+seed),fract(t));
}
void fragment() {
    float r=length(UV), angle=atan(UV.y,UV.x);
    float wall=smoothstep(.12,.55,r);
    vec3 color=mix(vec3(.065,.36,.43),vec3(.105,.44,.49),wall);
    float aa=max(fwidth(r),.0015);
    // Broad submerged facets share the spiral direction of the surface strokes.
    // Their slanted boundaries continue through the gaps instead of a flat dark backing.
    float flow=angle+clock*.19+r*7.0;
    float sector=floor(mod(flow,6.2831853)*3.8197186);
    float along=fract(mod(flow,6.2831853)*3.8197186);
    float bend=mix(hash(sector+61.0),hash(mod(sector+1.0,24.0)+61.0),along);
    float layer=floor(r*14.0+bend*1.6);
    float tone=hash(layer*9.3+sector*.71);
    vec3 submerged=mix(vec3(.10,.40,.46),vec3(.23,.59,.57),tone);
    color=mix(color,submerged,smoothstep(.12,.32,r)*.65);
    // Each overlapping stroke has its own reach, taper and angular silhouette.
    // Dark troughs occupy the same flow as the mint crests, including down the bowl.
    for(int i=0;i<12;i++) {
        float lane=float(i);
        float seed=lane*19.7+4.0;
        float theta=mod(angle+clock*.19-lane*2.399963,6.2831853);
        float span=2.5+hash(seed)*1.4;
        float t=theta/span;
        float envelope=clamp(min(t*8.0+.45,(1.0-t)*5.0+.40),0.0,1.0);
        float center=.235+mod(lane*5.0,12.0)*.060;
        center+=.22*(.5-t)+.045*(edge(theta*3.0,seed)-.5);
        float width=(.052+hash(seed+2.0)*.035)*envelope;
        float near_edge=center-width*(.55+edge(theta*4.0,seed+8.0));
        float far_edge=center+width*(.55+edge(theta*3.2,seed+16.0));
        float active=smoothstep(0.0,.025,theta)*(1.0-smoothstep(span-.025,span,theta));
        float trough=(smoothstep(near_edge-width*.45-aa,near_edge-width*.45+aa,r)
                    -smoothstep(far_edge+aa,far_edge+aa*3.0,r))*active;
        vec3 dark=mix(vec3(.075,.35,.41),vec3(.10,.43,.47),hash(seed+6.0));
        color=mix(color,dark,trough*.35);
        float stroke=(smoothstep(near_edge-aa,near_edge+aa,r)
                     -smoothstep(far_edge-aa,far_edge+aa,r))*active;
        float facet=edge(theta*5.4,seed+31.0);
        vec3 mint=mix(vec3(.25,.63,.60),vec3(.49,.85,.74),hash(seed+3.0));
        // A shorter slanted light facet sits within the broad stroke; no outline rings.
        float ridge=center+width*(.2+.45*edge(theta*4.0,seed+44.0));
        float highlight=smoothstep(ridge-aa,ridge+aa,r)*smoothstep(.25,.65,facet);
        float core=1.0-smoothstep(.12,.85,abs(r-center)/max(width,.001));
        mint=mix(mint,vec3(.52,.85,.74),core*.35);
        mint=mix(mint,vec3(.64,.94,.82),highlight*.78);
        float slash=center+width*(edge(theta*6.0,seed+55.0)*1.8-1.1);
        float shade=(1.0-smoothstep(slash-aa,slash+aa,r))*.45;
        mint=mix(mint,vec3(.13,.47,.49),shade);
        color=mix(color,mint,stroke*(.76+.20*facet)*(1.0-smoothstep(.78,1.0,r)*.65));
    }
    color=mix(vec3(.065,.35,.42),color,smoothstep(.12,.27,r));
    ALBEDO=linear_color(color);
    float reach=r+.018*sin(angle*5.0+sin(angle*3.0));
    ALPHA=1.0-smoothstep(.87,1.0,reach);
}
