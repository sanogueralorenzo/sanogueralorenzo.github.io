instance uniform float light_through_surface : hint_range(0.0, 1.0) = 0.0;

void light() {
    float facing = dot(NORMAL, LIGHT);
    float facing_blend = clamp(fwidth(facing), .035, .10);
    float side = smoothstep(.08 - facing_blend, .08 + facing_blend, facing);
    float top = smoothstep(.45 - facing_blend, .45 + facing_blend, facing);
    float sunlight = max(side * .81 + top * .19, light_through_surface);
    float warm_pigment = smoothstep(.29, .68, ALBEDO.r - ALBEDO.g);
    vec3 cast_shadow = mix(vec3(.18, .19, .94), vec3(.38, .32, .83), warm_pigment);
    vec3 facing_shade = mix(vec3(.42,.43,1.02), vec3(.43,.36,.88), warm_pigment);
    vec3 daylight = LIGHT_COLOR / PI;
    vec3 local_light = mix(facing_shade, daylight, sunlight);
    vec3 transmitted_shadow = mix(cast_shadow, daylight, light_through_surface);
    DIFFUSE_LIGHT += mix(transmitted_shadow, local_light, ATTENUATION);
}
