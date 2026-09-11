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
    float current_coverage=0.0;
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
    for(int i=0;i<14;i++) {
        float lane=float(i);
        float seed=lane*19.7+4.0;
        float dominant=(i==0 || i==1 || i==4 || i==6) ? 1.0 : 0.0;
        float theta=mod(turn-lane*2.399963,6.2831853);
        bool scattered=i==2 || i==5 || i==7 || i>=8;
        float span=scattered ? .65+hash(seed)*1.15 : 2.2+hash(seed)*1.8;
        float t=theta/span;
        float envelope=clamp(min(t*8.0+.45,(1.0-t)*5.0+.40),0.0,1.0);
        float center=scattered ? .65+hash(seed+5.0)*.30 : .235+mod(lane*3.0,8.0)*.084;
        if(i==0) center=.16;
        center+=(.09+hash(seed+9.0)*.16)*(.5-t)+.09*(edge(theta*1.4,seed)-.5);
        float width=(scattered ? .018+hash(seed+2.0)*.035 : .058+hash(seed+2.0)*.050)*envelope;
        float near_edge=center-width*(.55+edge(theta*1.9,seed+8.0));
        float far_edge=center+width*(.55+edge(theta*1.5,seed+16.0));
        float active=smoothstep(0.0,.18,theta)*(1.0-smoothstep(span-.30,span,theta));
        float breakwater=smoothstep(.28,.38,t)*(1.0-smoothstep(.52,.64,t));
        active*=1.0-breakwater*smoothstep(.58,.78,center)*(scattered ? 0.0 : 1.0);
        float trough=(smoothstep(near_edge-width*.45-aa,near_edge-width*.45+aa,r)
                    -smoothstep(far_edge+aa,far_edge+aa*3.0,r))*active;
        vec3 dark=mix(vec3(.075,.35,.41),vec3(.10,.43,.47),hash(seed+6.0));
        color=mix(color,dark,trough*.35*(1.0-smoothstep(.53,.68,r)));
        float softness=width*.12+aa;
        float stroke=(smoothstep(near_edge-softness,near_edge+softness,r)
                     -smoothstep(far_edge-softness,far_edge+softness,r))*active;
        if(scattered) outer_coverage=max(outer_coverage,stroke);
        current_coverage=max(current_coverage,stroke);
        float facet=edge(theta*3.2,seed+31.0);
        vec3 mint=mix(vec3(.25,.63,.60),vec3(.49,.85,.74),hash(seed+3.0));
        // A shorter slanted light facet sits within the broad stroke; no outline rings.
        float ridge=center+width*(.2+.45*edge(theta*2.0,seed+44.0));
        float highlight=smoothstep(ridge-aa,ridge+aa,r)*smoothstep(.25,.65,facet);
        float core=1.0-smoothstep(.12,.85,abs(r-center)/max(width,.001));
        mint=mix(mint,vec3(.60,.93,.80),core*(.22+.40*dominant));
        mint=mix(mint,vec3(.64,.94,.82),highlight*.70);
        float slash=center+width*(edge(theta*3.1,seed+55.0)*1.8-1.1);
        float shade=(1.0-smoothstep(slash-aa,slash+aa,r))*.45;
        mint=mix(mint,vec3(.13,.47,.49),shade);
        // A handful of slanted patches sit within each smoothly curved water body.
        vec2 tile=vec2(theta*2.2,(r-center)/max(width,.001)*1.2+theta*.55);
        vec2 cell=floor(tile), local=fract(tile);
        float a=hash(cell.x*13.7+cell.y*31.1+seed);
        float b=hash((cell.x+1.0)*13.7+cell.y*31.1+seed);
        float c=hash(cell.x*13.7+(cell.y+1.0)*31.1+seed);
        float d=hash((cell.x+1.0)*13.7+(cell.y+1.0)*31.1+seed);
        float piece=local.x+local.y<1.0 ? a+(b-a)*local.x+(c-a)*local.y
                    : d+(c-d)*(1.0-local.x)+(b-d)*(1.0-local.y);
        vec3 tint=mix(vec3(.075,.36,.43),vec3(.43,.78,.70),smoothstep(.24,.68,piece));
        mint=mix(mint,tint,.28+.40*(1.0-smoothstep(.25,.43,piece)));
        float spark=(1.0-smoothstep(width*.045,width*.13,abs(r-ridge)))
                    *smoothstep(.60,.82,edge(theta*4.5,seed+72.0));
        mint=mix(mint,vec3(.68,.96,.83),spark*.68);
        float coverage=scattered ? .68 : 1.0-smoothstep(.67,1.0,r)*.82;
        // Break up the two supporting crests; keep the main mid-bowl crest (4) bright.
        if(i==1 || i==6) {
            float gap=smoothstep(.28,.68,edge(theta*1.65,seed+103.0))
                     *smoothstep(.28,.40,r)*(1.0-smoothstep(.64,.78,r));
            coverage*=1.0-gap*.52;
            mint=mix(mint,vec3(.12,.44,.49),gap*.25);
        }
        color=mix(color,mint,clamp(stroke*(.60+.36*facet+dominant*.10)*coverage,0.0,1.0));
    }
    // Carry a faint broken current through bare shelf patches without repainting existing crests.
    float shelf_band=smoothstep(.52,.64,r)*(1.0-smoothstep(.80,.87,r));
    float ripple=.5+.5*sin(turn*2.0+r*34.0+(tone-.5)*2.2);
    float broken=smoothstep(.22,.65,tone);
    float infill=shelf_band*(1.0-smoothstep(.05,.35,current_coverage))
                 *smoothstep(.38,.88,ripple)*(.32+.35*broken);
    color=mix(color,mix(vec3(.20,.54,.55),vec3(.40,.75,.68),tone),infill);
    color=mix(vec3(.065,.35,.42),color,smoothstep(.045,.11,r));
    float reach=r+.018*sin(angle*5.0+sin(angle*3.0));
    // Remain opaque through Whirlpool3D.WaterCutout (.80); outer gaps reveal the ocean.
    float shelf=mix(1.0,.16+.84*outer_coverage,smoothstep(.80,.88,r));
    float water_alpha=(1.0-smoothstep(.87,1.0,reach))*shelf;
    // Twenty-four broken streaks stay near the lip with uneven spacing and radial offsets.
    float foam=0.0;
    if(r>.80 && r<1.08) for(int i=0;i<24;i++) {
        float lane=float(i), seed=lane*17.3+9.0;
        float theta=mod(turn-lane*2.399963-hash(seed)*.9,6.2831853);
        float span=.24+.24*hash(seed+1.0), u=theta/span;
        // A gentle outward pitch follows the rotation; angle-based slope keeps short pieces stable.
        // Including drift and soft edges, foam stays inside the .80–1.08 radius band.
        float outward_pitch=.12+.06*hash(seed+4.0);
        float arc=.895+.105*hash(seed+3.0)+outward_pitch*(theta-span*.5)
                 +.008*sin(theta*2.0+seed)+.006*sin(clock*.22+seed)-.012*(1.0-clamp(u,0.0,1.0));
        float width=(.0035+.005*hash(seed+2.0))*(.65+.35*sin(clamp(u,0.0,1.0)*3.14159265));
        float stroke=(1.0-smoothstep(width*.15,width*1.35+aa,abs(r-arc)))
                    *smoothstep(0.0,.24,u)*(1.0-smoothstep(.65,1.0,u));
        float gap_center=.30+.25*hash(seed+6.0);
        float gap=smoothstep(gap_center-.10,gap_center-.03,u)
                 *(1.0-smoothstep(gap_center+.03,gap_center+.11,u));
        stroke*=1.0-gap*(.65+.30*hash(seed+7.0));
        // Longer marks break twice instead of reading as paired motion outlines.
        float second_gap=smoothstep(.65,.70,u)*(1.0-smoothstep(.76,.83,u));
        stroke*=1.0-second_gap*smoothstep(.34,.46,span)*.85;
        float fade=.30+.70*smoothstep(-.6,.8,sin(clock*(.25+.16*hash(seed+8.0))+seed));
        foam=max(foam,stroke*fade*.39);
    }
    float alpha=water_alpha+foam*(1.0-water_alpha);
    vec3 foam_color=mix(vec3(.55,.80,.75),vec3(.88,.87,.73),smoothstep(.72,.93,tone)*.45);
    foam_color=mix(vec3(.28,.62,.60),foam_color,smoothstep(.86,.99,r));
    color=mix(color,foam_color,foam/max(alpha,.0001));
    ALBEDO=linear_color(color);
    ALPHA=alpha;
}
