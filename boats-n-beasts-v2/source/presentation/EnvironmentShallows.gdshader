shader_type spatial;
render_mode cull_disabled, depth_draw_never, ambient_light_disabled, specular_disabled;
uniform float clock = 0.0;

vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }

float crest(float depth, float center, float width, float aa) {
    return 1.0 - smoothstep(width*.68, width + aa, abs(depth - center));
}

void fragment() {
    float angle = UV.x;
    float depth = UV.y;
    float aa = max(fwidth(depth)*.58, .004);
    float inner_edge = .185 + .064*sin(angle*3.0 + .6) + .025*sin(angle*8.0 - .35);
    float middle_edge = inner_edge + .139 + .052*sin(angle*5.0 - .65) + .021*sin(angle*2.0 + 1.2);
    float lobe_angle = angle*3.0 - .5;
    float lobes = .72*sin(lobe_angle) + .28*sin(angle*7.0 + 1.1);
    float extension = smoothstep(-.44, .72, lobes);
    float reef_phase = fract(lobe_angle/TAU + .12 + .07*sin(angle*2.0 + .9));
    float tongue = max(0.0, min((reef_phase - .19)/.29, (.59 - reef_phase)/.11));
    tongue *= .77 + .23*sin(angle + 1.6);
    float outer_distance = depth - (middle_edge + mix(.018,.198,extension) + .124*tongue);
    float outer_aa = max(fwidth(outer_distance)*.58, .004);
    float feather = mix(.035,.015,max(extension,tongue));
    vec3 inner = vec3(.32,.787,.655);
    vec3 middle = vec3(.19,.714,.604);
    vec3 outer = vec3(.076,.638,.60);
    vec3 color = mix(inner, middle, smoothstep(inner_edge-aa,inner_edge+aa,depth));
    float reef_distance = depth - (middle_edge + .063*tongue);
    float reef_aa = max(fwidth(reef_distance)*.58, .004);
    float seaward = smoothstep(-reef_aa,reef_aa,reef_distance) * mix(.24,1.0,max(extension,tongue));
    color = mix(color, outer, seaward);

    float curl = .019*sin(angle*13.0 + clock*.65) + .011*sin(angle*31.0 - clock*.27);
    float shape = sin(angle*9.0)*sin(angle*13.0) + .44*sin(angle*29.0 + clock*.65);
    float first = crest(depth, .052 + curl, .023 + .007*sin(angle*17.0), aa);
    first *= smoothstep(-.68,-.35,shape);
    float reach = .135 + .049*sin(angle*4.0 - clock*.84);
    float second = crest(depth, reach + curl*.6, .009 + .006*sin(angle*11.0), aa);
    second *= smoothstep(.07,.29,shape + .26*sin(angle*23.0));
    float foam = max(first, second*.94);
    ALBEDO = linear_color(mix(color, vec3(.96,.972,.924), foam));
    ALPHA = 1.0 - smoothstep(-outer_aa,feather+outer_aa,outer_distance);
}

void light() {
    DIFFUSE_LIGHT += mix(vec3(.72,.72,.88), vec3(1.0), ATTENUATION);
}
