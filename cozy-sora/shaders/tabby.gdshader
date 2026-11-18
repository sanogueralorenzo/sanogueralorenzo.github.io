shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shared/surface_noise.gdshaderinc"

varying vec3 coat;
void vertex() {
    coat = VERTEX;
}

void fragment() {
    float back = smoothstep(-0.02, 0.075, coat.y);
    float side = abs(coat.x);
    float growth = coat.z * 104.0 + side * 21.0 + sin(coat.z * 31.0 + coat.y * 17.0);
    float fibre = noise(vec2(coat.z * 170.0, (side + coat.y * 0.58) * 1800.0));
    float stripe = smoothstep(0.28, 0.85, cos(growth + fibre * 0.55 + coat.y * 23.0));
    float spine = (1.0 - smoothstep(0.006, 0.031, side)) * back;
    vec3 pigment = mix(vec3(0.47, 0.206, 0.068), vec3(0.18, 0.071, 0.027), max(stripe * (0.45 + 0.50 * back), spine));
    float bib = 1.0 - smoothstep(-0.09, -0.025, coat.y + 0.015 * sin(growth * 0.22));
    ALBEDO = mix(pigment, vec3(0.78, 0.66, 0.49), bib) * (0.82 + 0.36 * fibre);
    ROUGHNESS = 0.82;
    RIM = 0.17;
    RIM_TINT = 0.72;
}
