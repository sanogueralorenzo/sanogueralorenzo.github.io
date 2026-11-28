instance uniform float light_through_surface : hint_range(0.0, 1.0) = 0.0;

varying vec3 pigment_position;

float brush_mark(vec3 p) {
    float line = dot(p, vec3(22.0, -17.0, 12.0));
    line += .24 * sin(dot(p, vec3(5.0, 3.0, -4.0)));
    float filter_width = clamp(fwidth(line), .04, .48);
    float groove = 1.0 - smoothstep(.07, .07 + filter_width, abs(fract(line) - .5));
    float broken = smoothstep(-.4, .7, sin(dot(p, vec3(6.0, 4.0, 9.0))) + .42 * cos(p.y * 13.0));
    return groove * broken * (1.0 - smoothstep(.24, .5, filter_width));
}

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
    vec3 lit = mix(transmitted_shadow, local_light, ATTENUATION);
    float shade = 1.0 - sunlight * ATTENUATION;
    float ink = brush_mark(pigment_position) * (.08 + .30 * shade);
    float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.8) * max(facing, 0.0) * ATTENUATION;
    DIFFUSE_LIGHT += lit * mix(vec3(1.0), vec3(.58,.46,.69), ink) + edge * vec3(.24,.13,.04);
}
