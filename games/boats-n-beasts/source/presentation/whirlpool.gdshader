shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform float clock = 0.0;
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),c)); }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float water_noise(vec2 p) {
    vec2 cell = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),
        mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
void fragment() {
    float r = length(UV);
    float angle = atan(UV.y, UV.x);
    // Advect broad patches inward. Warped widths and coverage break the regular spiral.
    float flow = angle + 1.35 * log(max(r,.09)) + clock * .32;
    vec2 drift = vec2(cos(flow),sin(flow)) * (1.8+r*2.0);
    float eddy = water_noise(drift*1.35 + vec2(r*2.0,-r));
    float phase = flow*3.0 + (eddy-.5)*2.8 + .35*sin(angle*2.0+r*9.0);
    float coverage = smoothstep(.15,.72,water_noise(drift*.85+vec2(5.3,r*3.0)));
    float ribbon = pow(.5+.5*sin(phase),1.7) * (.40+.60*coverage);
    float wash = water_noise(drift*2.3+vec2(r*5.0,2.1));
    float wall = smoothstep(.10,.67,r);
    vec3 color = mix(vec3(.025,.34,.40),vec3(.045,.45,.49),wall);
    // Large turquoise washes continue down the throat, retaining the sea's hue.
    color += vec3(.035,.095,.085) * (wash-.35) * (1.0-smoothstep(.7,1.0,r));
    float current = smoothstep(.15,.34,r) * (1.0-smoothstep(.80,1.0,r));
    color = mix(color,vec3(.20,.68,.62),ribbon*current*.85);
    float edge = pow(.5+.5*sin(phase+.35),9.0) * coverage;
    color = mix(color,vec3(.38,.78,.69),edge*current*.20);
    ALBEDO = linear_color(color);
    // Irregular, softly fading outer washes rather than a circular rim.
    float reach = r + (water_noise(drift*1.1)-.5)*.10*smoothstep(.72,1.0,r);
    ALPHA = 1.0-smoothstep(.83,1.0,reach);
}
