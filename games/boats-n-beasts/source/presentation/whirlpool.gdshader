shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float clock = 0.0;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(float p) { return fract(sin(p*127.1)*43758.5453); }
// Smooth, unequal bends establish the flow; finer facets remain inside each water mass.
float edge(float t, float seed) {
    float k=floor(t);
    float f=fract(t);
    return mix(hash(k+seed),hash(k+1.0+seed),mix(f,f*f*(3.0-2.0*f),.8));
}
void fragment() {
    float r=length(UV), angle=atan(UV.y,UV.x);
    float turn=angle-clock*.19;
    float wall=smoothstep(.12,.55,r);
    vec3 color=mix(vec3(.065,.36,.43),vec3(.105,.44,.49),wall);
    float aa=max(fwidth(r),.003);
    float outer_coverage=0.0;
    // Broad submerged facets share the spiral direction of the surface strokes.
    // Their slanted boundaries continue through the gaps instead of a flat dark backing.
    float flow=turn+r*7.0;
    vec2 bed=vec2(cos(flow),sin(flow))*(2.0+r*4.0);
    vec2 bed_cell=floor(bed), bed_local=fract(bed);
    float bed_a=hash(bed_cell.x*13.1+bed_cell.y*27.7);
    float bed_b=hash((bed_cell.x+1.0)*13.1+bed_cell.y*27.7);
    float bed_c=hash(bed_cell.x*13.1+(bed_cell.y+1.0)*27.7);
    float tone=mix(mix(bed_a,bed_b,bed_local.x),bed_c,bed_local.y);
    color=mix(color,mix(vec3(.10,.40,.46),vec3(.23,.59,.57),tone),smoothstep(.10,.35,r)*.35);
    float inner_wall=smoothstep(.075,.13,r)*(1.0-smoothstep(.22,.38,r));
    color=mix(color,mix(vec3(.13,.45,.51),vec3(.28,.65,.62),tone),inner_wall*.75);
    // Broad currents descend into the throat; shorter washes scatter across the outer shelf.
    // Dark troughs occupy the same flow as the mint crests, including down the bowl.
    for(int i=0;i<12;i++) {
        float lane=float(i);
        float seed=lane*19.7+4.0;
        float dominant=(i==0 || i==1 || i==4 || i==6) ? 1.0 : 0.0;
        bool scattered=i==2 || i==5 || i==7 || i>=8;
        // Offset each current in the rotating water plane so adjacent paths diverge and overlap.
        vec2 offset=vec2(cos(seed),sin(seed))*(i==0 ? 0.0 : scattered ? .11 : .065);
        vec2 current=vec2(cos(turn),sin(turn))*r-offset;
        float current_radius=length(current);
        float theta=mod(atan(current.y,current.x)-lane*2.399963,6.2831853);
        float span=scattered ? .75+hash(seed)*1.35 : 2.0+hash(seed)*1.5;
        float t=theta/span;
        float envelope=clamp(min(t*8.0+.45,(1.0-t)*5.0+.40),0.0,1.0);
        float center=scattered ? .65+hash(seed+5.0)*.30 : .235+mod(lane*3.0,8.0)*.084;
        if(i==0) center=.16;
        center+=(.09+hash(seed+9.0)*.16)*(.5-t)+.09*(edge(theta*1.4,seed)-.5);
        float width=(scattered ? .036+hash(seed+2.0)*.055 : .090+hash(seed+2.0)*.060)*envelope;
        if(i==0) width=(.058+hash(seed+2.0)*.050)*envelope;
        float near_edge=center-width*(.55+edge(theta*1.9,seed+8.0));
        float far_edge=center+width*(.55+edge(theta*1.5,seed+16.0));
        float active=smoothstep(0.0,.18,theta)*(1.0-smoothstep(span-.30,span,theta));
        float breakwater=smoothstep(.28,.38,t)*(1.0-smoothstep(.52,.64,t));
        active*=1.0-breakwater*smoothstep(.58,.78,center)*(scattered ? 0.0 : 1.0);
        float wash_softness=max(width*.65,aa);
        float wash=(smoothstep(near_edge-wash_softness,near_edge,current_radius)
                   -smoothstep(far_edge,far_edge+wash_softness,current_radius))*active;
        color=mix(color,vec3(.19,.53,.55),wash*(scattered ? .12 : .34));
        float trough=(smoothstep(near_edge-width*.45-aa,near_edge-width*.45+aa,current_radius)
                    -smoothstep(far_edge+aa,far_edge+aa*3.0,current_radius))*active;
        vec3 dark=mix(vec3(.075,.35,.41),vec3(.10,.43,.47),hash(seed+6.0));
        color=mix(color,dark,trough*.35*(1.0-smoothstep(.53,.68,current_radius)));
        float softness=width*.12+aa;
        float stroke=(smoothstep(near_edge-softness,near_edge+softness,current_radius)
                     -smoothstep(far_edge-softness,far_edge+softness,current_radius))*active;
        if(scattered) outer_coverage=max(outer_coverage,stroke);
        float facet=edge(theta*3.2,seed+31.0);
        float crest_run=smoothstep(.28,.65,edge(theta*1.4,seed+81.0));
        vec3 mint=mix(vec3(.25,.63,.60),vec3(.49,.85,.74),hash(seed+3.0));
        // A shorter slanted light facet sits within the broad stroke; no outline rings.
        float ridge=center+width*(.2+.45*edge(theta*2.0,seed+44.0));
        float highlight=smoothstep(ridge-aa,ridge+aa,current_radius)*smoothstep(.25,.65,facet);
        float core=1.0-smoothstep(.12,.85,abs(current_radius-center)/max(width,.001));
        mint=mix(mint,vec3(.60,.93,.80),core*(.25+.45*dominant)*(.45+.55*crest_run));
        mint=mix(mint,vec3(.64,.94,.82),highlight*.70*crest_run);
        float slash=center+width*(edge(theta*3.1,seed+55.0)*1.8-1.1);
        float shade=(1.0-smoothstep(slash-aa,slash+aa,current_radius))*.45;
        mint=mix(mint,vec3(.13,.47,.49),shade);
        // A handful of slanted patches sit within each smoothly curved water body.
        vec2 tile=vec2(theta*2.2,(current_radius-center)/max(width,.001)*1.2+theta*.55);
        vec2 cell=floor(tile), local=fract(tile);
        float a=hash(cell.x*13.7+cell.y*31.1+seed);
        float b=hash((cell.x+1.0)*13.7+cell.y*31.1+seed);
        float c=hash(cell.x*13.7+(cell.y+1.0)*31.1+seed);
        float d=hash((cell.x+1.0)*13.7+(cell.y+1.0)*31.1+seed);
        float piece=local.x+local.y<1.0 ? a+(b-a)*local.x+(c-a)*local.y
                    : d+(c-d)*(1.0-local.x)+(b-d)*(1.0-local.y);
        vec3 tint=mix(vec3(.075,.36,.43),vec3(.43,.78,.70),smoothstep(.24,.68,piece));
        mint=mix(mint,tint,.28+.40*(1.0-smoothstep(.25,.43,piece)));
        float spark=(1.0-smoothstep(width*.045,width*.13,abs(current_radius-ridge)))
                    *smoothstep(.60,.82,edge(theta*4.5,seed+72.0));
        mint=mix(mint,vec3(.68,.96,.83),spark*.68*crest_run);
        // Broad slanted troughs cut into the crests, leaving clear dark water between light masses.
        float wedge_edge=center+width*(-.50+1.1*(t-.5)+.65*edge(theta*1.8,seed+95.0));
        float wedge_softness=max(width*.16,aa);
        float wedge=(1.0-smoothstep(wedge_edge-wedge_softness,wedge_edge+wedge_softness,current_radius))
                    *smoothstep(.25,.55,edge(theta*1.6,seed+92.0));
        mint=mix(mint,vec3(.075,.36,.43),wedge*.72);
        float coverage=scattered ? .68 : 1.0-smoothstep(.67,1.0,r)*.82;
        color=mix(color,mint,clamp(stroke*(.60+.36*facet+dominant*.10)*coverage,0.0,1.0));
    }
    color=mix(vec3(.065,.35,.42),color,smoothstep(.045,.11,r));
    ALBEDO=linear_color(color);
    float reach=r+.018*sin(angle*5.0+sin(angle*3.0));
    // Remain opaque through Whirlpool3D.WaterCutout (.80); outer gaps reveal the ocean.
    float shelf=mix(1.0,.16+.84*outer_coverage,smoothstep(.80,.88,r));
    ALPHA=(1.0-smoothstep(.87,1.0,reach))*shelf;
}
