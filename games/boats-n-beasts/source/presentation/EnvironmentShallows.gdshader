shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 shallow_color : source_color = vec4(0.25, 0.53, 0.48, 1.0);
uniform vec4 deep_color : source_color = vec4(0.082, 0.34, 0.38, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
void fragment() {
    // Local mesh UVs stay attached to the island. No time source or radial glow.
    vec2 p = UV;
    float n = noise(p*2.3) * .58 + noise(p*7.1) * .30 + noise(p*21.0) * .12;
    vec3 tint = mix(deep_color.rgb, shallow_color.rgb, smoothstep(.12,.85,n));
    ALBEDO = tint;
    // Mesh geometry already selects two broad coves. Physical meshes supply submerged rocks.
    ALPHA = clamp(COLOR.a * (.58 + n*.32) - (1.0-n)*.10, 0.0, .84);
}
