shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float clock = 0.0;
uniform vec2 camera_offset = vec2(0.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
float clouds(vec2 p) {
    float value = 0.0, amplitude = .55;
    mat2 turn = mat2(vec2(.8, -.6), vec2(.6, .8));
    for (int i = 0; i < 4; i++) {
        value += noise(p) * amplitude;
        p = turn * p * 2.03 + vec2(17.1, 9.2);
        amplitude *= .48;
    }
    return value;
}
void fragment() {
    // Camera-relative plane, continuous world sampling: no seams or wrapping jumps.
    vec2 view = (UV - .5) * 36.0;
    vec2 far_p = view + camera_offset * .10 + vec2(clock * .0018, -clock * .0006);
    vec2 warp = vec2(noise(far_p * .32), noise(far_p * .32 + 8.7)) - .5;
    float deep = clouds(far_p * .65 + warp * 2.4);
    float middle = clouds(view * 1.35 + camera_offset * .27 + vec2(-clock * .003, clock * .001));
    float veil = clouds(view * 2.1 + camera_offset * .48 + vec2(clock * .005, clock * .0015));
    vec3 color = mix(vec3(.022,.052,.092), vec3(.052,.135,.165), smoothstep(.20,.72,deep));
    // Broad muted cloud banks, with light catching one side rather than a flat noise wash.
    float bank = smoothstep(.43,.77,middle);
    float light_side = clouds(view * 1.35 + camera_offset * .27 + vec2(-.18,-.25) + vec2(-clock*.003,clock*.001));
    vec3 cloud_color = mix(vec3(.065,.13,.18),vec3(.17,.265,.29),smoothstep(-.04,.09,light_side-middle));
    color = mix(color,cloud_color,bank*.68);
    color += vec3(.055,.08,.085) * smoothstep(.63,.86,veil) * .30;
    ALBEDO = color;
}
