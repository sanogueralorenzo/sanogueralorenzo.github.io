shader_type spatial;
render_mode unshaded, fog_disabled;
#include "res://shared/water_waves.gdshaderinc"

uniform sampler2D sky_panorama : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_direction;
varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world);
    float distance_to_eye = length(world - CAMERA_POSITION_WORLD);
    vec2 p = world.xz;
    float bend = sin(p.y * 0.054 + sin(p.x * 0.018)) * 1.4;
    vec2 swell = wave_slope(p, vec2(0.57, 0.82), 0.31, 0.075, TIME * 0.75 + bend);
    swell += wave_slope(p, vec2(-0.23, 0.97), 0.58, 0.035, TIME * 1.05 - bend);
    vec3 normal = normalize(water_normal(p, TIME, 0.59) + vec3(swell.x, 0.0, swell.y));
    vec3 reflected = reflect(-to_eye, normal);
    vec2 uv = vec2(atan(reflected.x, -reflected.z) / TAU, acos(clamp(abs(reflected.y), 0.0, 1.0)) / PI);
    vec3 sky = textureLod(sky_panorama, uv, mix(3.5, 5.4, smoothstep(80.0, 850.0, distance_to_eye))).rgb;
    float fresnel = 0.021 + 0.979 * pow(1.0 - max(dot(to_eye, normal), 0.0), 5.0);
    float crest = smoothstep(-0.1, 0.12, swell.y) * (1.0 - smoothstep(80.0, 440.0, distance_to_eye));
    vec3 water = mix(vec3(0.011, 0.067, 0.091), vec3(0.014, 0.091, 0.112), crest);
    float glint = pow(max(dot(reflected, sun_direction), 0.0), 860.0);
    vec3 radiance = mix(water, sky * vec3(0.82, 0.88, 0.9), fresnel) + vec3(2.4, 2.0, 1.6) * glint;
    ALBEDO = mix(radiance, vec3(0.35, 0.48, 0.57), smoothstep(240.0, 1800.0, distance_to_eye) * 0.81);
}
