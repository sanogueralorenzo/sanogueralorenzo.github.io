shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.235, 0.455, 0.431, 1.0);
uniform vec4 deep_color : source_color = vec4(0.047, 0.208, 0.247, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
void fragment() {
    // Local mesh UVs stay attached to the island. No time source or radial glow.
    vec2 p = UV;
    float n = noise(p*5.1) * .65 + noise(p*13.7) * .25 + noise(p*31.0) * .10;
    vec3 tint = mix(deep_color.rgb, shallow_color.rgb, smoothstep(.12,.85,n));
    float stone = 0.0;
    vec2 grid = p * 7.0;
    for (int y=-1; y<=1; y++) for (int x=-1; x<=1; x++) {
        vec2 cell = floor(grid) + vec2(float(x),float(y));
        float h = hash(cell);
        vec2 center = cell + vec2(.2 + .6*h, .2 + .6*hash(cell+17.0));
        vec2 delta = (grid-center) * vec2(1.0, .7 + h*.8);
        float radius = .14 + .23*hash(cell+9.0);
        float patch = 1.0 - smoothstep(radius*.7, radius, length(delta) + .035*noise(p*45.0));
        stone = max(stone, patch * step(.36,h));
    }
    tint = mix(tint, deep_color.rgb*.77, stone*.72);
    ALBEDO = tint;
    // Noise breaks the shallow edge into coves, rather than painting a uniform luminous rim.
    ALPHA = clamp((COLOR.a - (1.0-n)*.35) * (0.58 + n*.34), 0.0, .79);
}
