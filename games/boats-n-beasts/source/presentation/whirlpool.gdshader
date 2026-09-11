shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float clock = 0.0;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
void fragment() {
    float r = length(UV);
    float angle = atan(UV.y, UV.x);
    // Continuous advection: broad curls rotate while finer foam travels down the bowl.
    float winding = angle + 2.6 * log(max(r, .065)) + clock * .42;
    float bend = .42 * sin(angle * 5.0 + r * 12.0 - clock * .17);
    float broad = pow(.5 + .5 * sin(winding * 3.0 + bend), 3.0);
    float threads = pow(.5 + .5 * sin(winding * 9.0 + sin(r * 24.0 - clock * .9)), 15.0);
    float patches = .5 + .5 * sin(angle * 7.0 - r * 19.0 - clock * .55);
    float foam = pow(.5 + .5 * sin(winding * 5.0 + .45 * sin(angle * 3.0)), 22.0) * smoothstep(.28, .85, patches);
    float wall = smoothstep(.12, .64, r);
    vec3 color = mix(vec3(.015,.17,.22), vec3(.045,.46,.49), wall);
    color += vec3(.018,.065,.065) * sin(angle - .6) * wall;
    float current = smoothstep(.12,.29,r) * (1.0 - smoothstep(.82,1.0,r));
    color = mix(color, vec3(.18,.69,.64), broad * current * .88);
    color = mix(color, vec3(.29,.76,.68), threads * current * .24);
    color = mix(color, vec3(.64,.88,.75), foam * current * .58);
    // A shaded throat and uneven glints suggest depth without a black painted disk.
    color = mix(vec3(.008,.10,.14), color, smoothstep(.06,.21,r));
    ALBEDO = linear_color(color);
    ALPHA = 1.0 - smoothstep(.86,1.0,r);
}
